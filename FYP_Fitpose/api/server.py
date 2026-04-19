from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict

import cv2
import mediapipe as mp
import numpy as np
from fastapi import FastAPI, File, HTTPException, Query, UploadFile
import pickle
import pandas as pd
from tensorflow.keras.models import load_model


# =============================
# CONFIG
# =============================
BASE_DIR = Path(__file__).resolve().parent.parent
MODELS_DIR = BASE_DIR / "models"

MODEL_FILES = {
    "pushup": "pushup_lstm_30f_stride_2.h5",
    "deadlift": "deadlift_lstm_model.h5",
    "plank": "plank_model.pkl",
    "bicep": "bicep_curl_model.pkl",
}

SCALER_FILES = {
    "plank": "plank_input_scaler.pkl",
    "bicep": "bicep_curl_input_scaler.pkl",
}

EXERCISE_ALIASES = {
    "pushup": "pushup",
    "push-ups": "pushup",
    "push_ups": "pushup",
    "push ups": "pushup",
    "deadlift": "deadlift",
    "dealift": "deadlift",
    "deallift": "deadlift",
    "plank": "plank",
    "bicep": "bicep",
    "bicep curl": "bicep",
    "bicep_curl": "bicep",
}

PRED_BUFFER = 5
POSE_CONFIRM_FRAMES = 5
PLANK_CONFIDENCE_THRESHOLD = 0.6
BICEP_CONFIDENCE_THRESHOLD = 0.95
PUSHUP_SEQUENCE_LENGTH = 15

PLANK_LANDMARKS = [
    "NOSE",
    "LEFT_SHOULDER", "RIGHT_SHOULDER",
    "LEFT_ELBOW", "RIGHT_ELBOW",
    "LEFT_WRIST", "RIGHT_WRIST",
    "LEFT_HIP", "RIGHT_HIP",
    "LEFT_KNEE", "RIGHT_KNEE",
    "LEFT_ANKLE", "RIGHT_ANKLE",
    "LEFT_HEEL", "RIGHT_HEEL",
    "LEFT_FOOT_INDEX", "RIGHT_FOOT_INDEX",
]

BICEP_LANDMARKS = [
    "NOSE",
    "LEFT_SHOULDER", "RIGHT_SHOULDER",
    "RIGHT_ELBOW", "LEFT_ELBOW",
    "RIGHT_WRIST", "LEFT_WRIST",
    "LEFT_HIP", "RIGHT_HIP",
]


@dataclass
class ModelConfig:
    model: Any
    kind: str
    sequence_length: int
    feature_dim: int
    scaler: Any = None


# =============================
# LOAD MODELS
# =============================
def get_model_input_shape(model: Any):
    shape = model.input_shape
    # Keras may return a list for multi-input models; we use the first input.
    if isinstance(shape, list):
        shape = shape[0]
    return shape


def load_pickle_model(model_path: Path, scaler_path: Path | None = None):
    with open(model_path, "rb") as model_file:
        model = pickle.load(model_file)

    scaler = None
    if scaler_path and scaler_path.exists():
        with open(scaler_path, "rb") as scaler_file:
            scaler = pickle.load(scaler_file)

    return model, scaler


def load_exercise_models() -> Dict[str, ModelConfig]:
    loaded = {}
    missing = []

    for exercise, file_name in MODEL_FILES.items():
        model_path = MODELS_DIR / file_name
        if not model_path.exists():
            missing.append(f"{exercise}: {model_path}")
            continue

        if model_path.suffix.lower() == ".h5":
            loaded_model = load_model(str(model_path))
            input_shape = get_model_input_shape(loaded_model)

            if exercise == "pushup":
                seq_len = 15                    # Reduced from 30 → much faster feedback
                feat_dim = int(input_shape[2]) if input_shape and input_shape[2] else 8
            else:
                seq_len = int(input_shape[1]) if input_shape and input_shape[1] else 30
                feat_dim = int(input_shape[2]) if input_shape and input_shape[2] else 8

            loaded[exercise] = ModelConfig(
                model=loaded_model,
                kind="lstm",
                sequence_length=seq_len,
                feature_dim=feat_dim,
            )
            print(
                f"Model loaded for {exercise}: {model_path} "
                f"(sequence_length={seq_len}, feature_dim={feat_dim})"
            )
        else:
            scaler_file = MODELS_DIR / SCALER_FILES.get(exercise, "")
            loaded_model, scaler = load_pickle_model(model_path, scaler_file)
            feature_dim = len(PLANK_LANDMARKS) * 4 if exercise == "plank" else len(BICEP_LANDMARKS) * 4

            loaded[exercise] = ModelConfig(
                model=loaded_model,
                kind="sklearn",
                sequence_length=1,
                feature_dim=feature_dim,
                scaler=scaler,
            )
            print(
                f"Model loaded for {exercise}: {model_path} "
                f"(feature_dim={feature_dim})"
            )

    if not loaded:
        raise RuntimeError("No model files found. Server cannot start.")

    if missing:
        print("Missing model files:")
        for item in missing:
            print(f"  - {item}")

    return loaded


models = load_exercise_models()


# =============================
# MEDIAPIPE
# =============================
mp_pose = mp.solutions.pose
pose = mp_pose.Pose(
    static_image_mode=False,
    model_complexity=1,
    min_detection_confidence=0.5,
    min_tracking_confidence=0.5,
)


# =============================
# ANGLE FUNCTIONS
# =============================
def normalize_landmarks(landmarks):
    hip_center = (landmarks[23] + landmarks[24]) / 2
    return landmarks - hip_center


def calculate_angle(a, b, c):
    ba = a - b
    bc = c - b
    cosine = np.dot(ba, bc) / (np.linalg.norm(ba) * np.linalg.norm(bc) + 1e-6)
    return np.degrees(np.arccos(np.clip(cosine, -1.0, 1.0)))


def extract_angles(landmarks):
    l = normalize_landmarks(landmarks)
    return np.array(
        [
            calculate_angle(l[11], l[13], l[15]),
            calculate_angle(l[12], l[14], l[16]),
            calculate_angle(l[13], l[11], l[23]),
            calculate_angle(l[14], l[12], l[24]),
            calculate_angle(l[11], l[23], l[25]),
            calculate_angle(l[12], l[24], l[26]),
            calculate_angle(l[23], l[25], l[27]),
            calculate_angle(l[24], l[26], l[28]),
        ],
        dtype=np.float32,
    )


def extract_deadlift_features(landmarks):
    l = normalize_landmarks(landmarks)
    angles = np.array(
        [
            calculate_angle(l[11], l[23], l[25]),
            calculate_angle(l[12], l[24], l[26]),
            calculate_angle(l[23], l[25], l[27]),
            calculate_angle(l[24], l[26], l[28]),
            calculate_angle(l[7], l[11], l[23]),
            calculate_angle(l[8], l[12], l[24]),
            calculate_angle(l[13], l[11], l[23]),
            calculate_angle(l[14], l[12], l[24]),
        ],
        dtype=np.float32,
    )
    hip_height = np.array([(l[23][1] + l[24][1]) / 2], dtype=np.float32)
    return np.concatenate([angles, hip_height], axis=0)


def extract_base_features(exercise: str, landmarks):
    if exercise == "deadlift":
        return extract_deadlift_features(landmarks)
    return extract_angles(landmarks)


def extract_important_keypoints(landmarks, important_landmarks):
    row = []
    for name in important_landmarks:
        lm = landmarks[mp_pose.PoseLandmark[name].value]
        row.extend([lm.x, lm.y, lm.z, lm.visibility])
    return np.array(row, dtype=np.float32)


def predict_plank(model_config: ModelConfig, landmarks):
    row = extract_important_keypoints(landmarks, PLANK_LANDMARKS)
    X = pd.DataFrame([row])
    if model_config.scaler is not None:
        X = pd.DataFrame(model_config.scaler.transform(X))

    predicted_class = model_config.model.predict(X)[0]
    proba = model_config.model.predict_proba(X)[0]
    confidence = float(round(proba[int(np.argmax(proba))], 2))

    if predicted_class == "C" and confidence >= PLANK_CONFIDENCE_THRESHOLD:
        return "Correct", confidence, "Good form! Hold steady."
    if predicted_class == "L" and confidence >= PLANK_CONFIDENCE_THRESHOLD:
        return "Incorrect", confidence, "Low back detected. Drop your hips down."
    if predicted_class == "H" and confidence >= PLANK_CONFIDENCE_THRESHOLD:
        return "Incorrect", confidence, "High back detected. Raise your hips up."

    return "Analyzing...", confidence, "Hold position while the model stabilizes."


def predict_bicep(model_config: ModelConfig, landmarks):
    row = extract_important_keypoints(landmarks, BICEP_LANDMARKS)
    X = pd.DataFrame([row])
    if model_config.scaler is not None:
        X = pd.DataFrame(model_config.scaler.transform(X))

    predicted_class = model_config.model.predict(X)[0]
    proba = model_config.model.predict_proba(X)[0]
    confidence = float(round(proba[int(np.argmax(proba))], 2))

    if predicted_class == "L" and confidence >= BICEP_CONFIDENCE_THRESHOLD:
        return "Incorrect", confidence, "Lean too far back. Keep your torso upright."

    if confidence >= BICEP_CONFIDENCE_THRESHOLD:
        return "Correct", confidence, "Good form!"

    return "Analyzing...", confidence, "Hold position while the model stabilizes."


def match_feature_dim(features: np.ndarray, target_dim: int) -> np.ndarray:
    if features.shape[0] == target_dim:
        return features.astype(np.float32)

    if features.shape[0] > target_dim:
        return features[:target_dim].astype(np.float32)

    pad_len = target_dim - features.shape[0]
    padded = np.concatenate([features, np.zeros(pad_len, dtype=np.float32)])
    return padded.astype(np.float32)


def get_posture_feedback(exercise: str, angles, landmarks):
    if exercise != "pushup":
        return f"{exercise.capitalize()} posture needs adjustment. Keep your form controlled."

    feedback = []
    avg_elbow = np.mean(angles[0:2])
    avg_shoulder = np.mean(angles[2:4])
    avg_hip = np.mean(angles[4:6])
    avg_knee = np.mean(angles[6:8])

    if avg_hip < 155:
        feedback.append("Raise your hips! Keep your body in a straight line.")
    if avg_hip > 185:
        feedback.append("Do not arch your back. Keep hips aligned with shoulders.")
    if avg_knee < 160:
        feedback.append("Straighten your legs completely.")
    if avg_elbow > 165:
        feedback.append("Lower your body more by bending your elbows.")
    if avg_elbow < 70:
        feedback.append("Do not collapse. Push up higher.")
    if avg_shoulder < 150:
        feedback.append("Pull shoulders back and keep elbows closer to your sides.")

    avg_shoulder_x = (landmarks[11][0] + landmarks[12][0]) / 2
    avg_wrist_x = (landmarks[15][0] + landmarks[16][0]) / 2
    if avg_wrist_x < avg_shoulder_x - 0.08:
        feedback.append("Move your hands back under or slightly below your shoulders.")

    if not feedback:
        feedback.append("Minor form issue. Stay controlled and stable.")

    return " | ".join(feedback[:2])


def is_pushup_pose(landmarks):
    shoulder_y = (landmarks[11][1] + landmarks[12][1]) / 2
    hip_y = (landmarks[23][1] + landmarks[24][1]) / 2
    ankle_y = (landmarks[27][1] + landmarks[28][1]) / 2

    body_slope = abs(shoulder_y - hip_y) + abs(hip_y - ankle_y)
    if body_slope > 0.30:
        return False

    left_elbow = calculate_angle(landmarks[11], landmarks[13], landmarks[15])
    right_elbow = calculate_angle(landmarks[12], landmarks[14], landmarks[16])
    return 30 < left_elbow < 190 and 30 < right_elbow < 190


def is_pose_valid(exercise: str, landmarks):
    if exercise == "pushup":
        return is_pushup_pose(landmarks)
    return True


def parse_prediction_probability(pred_raw: np.ndarray) -> float:
    pred = np.array(pred_raw).squeeze()
    if pred.ndim == 0:
        return float(pred)

    if pred.size == 1:
        return float(pred[0])

    # If model is softmax with 2 outputs, assume index 1 means "incorrect".
    return float(pred[1])


def normalize_exercise_name(raw_exercise: str) -> str:
    key = (raw_exercise or "pushup").strip().lower()
    return EXERCISE_ALIASES.get(key, "")


# =============================
# STATE (PER-EXERCISE BUFFER)
# =============================
class SequenceState:
    def __init__(self, sequence_length: int):
        self.sequence_length = sequence_length
        self.sequence = deque(maxlen=sequence_length)
        self.pred_buffer = deque(maxlen=PRED_BUFFER)
        self.pose_counter = 0

    def clear(self):
        self.sequence.clear()
        self.pred_buffer.clear()
        self.pose_counter = 0


exercise_states = {}
for name, cfg in models.items():
    seq_len = 15 if name == "pushup" else cfg.sequence_length
    exercise_states[name] = SequenceState(seq_len)


# =============================
# FASTAPI
# =============================
app = FastAPI(title="FitPose Multi-Exercise Detection API")


@app.get("/")
def home():
    return {
        "status": "API running",
        "available_exercises": sorted(models.keys()),
        "default_exercise": "pushup",
    }


@app.get("/exercises")
def list_exercises():
    return {
        "available": sorted(models.keys()),
        "supported_aliases": sorted(EXERCISE_ALIASES.keys()),
    }


@app.post("/predict_frame")
async def predict_frame(
    file: UploadFile = File(...),
    exercise: str = Query(default="pushup"),
):
    normalized_exercise = normalize_exercise_name(exercise)
    if not normalized_exercise:
        raise HTTPException(
            status_code=400,
            detail=(
                "Invalid exercise. Use one of: "
                f"{', '.join(sorted(models.keys()))}"
            ),
        )

    if normalized_exercise not in models:
        raise HTTPException(
            status_code=503,
            detail=(
                f"Model for '{normalized_exercise}' is not loaded. "
                "Check model files in the models folder."
            ),
        )

    model_config = models[normalized_exercise]
    model = model_config.model

    contents = await file.read()
    np_arr = np.frombuffer(contents, np.uint8)
    frame = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
    if frame is None:
        raise HTTPException(status_code=400, detail="Invalid frame image")

    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    results = pose.process(rgb)

    label = "Processing"
    confidence = 0.0
    feedback = "Analyzing posture..."

    if results.pose_landmarks:
        landmarks = np.array([[lm.x, lm.y, lm.z] for lm in results.pose_landmarks.landmark])

        if normalized_exercise in ("pushup", "deadlift"):
            state = exercise_states[normalized_exercise]

            if is_pose_valid(normalized_exercise, landmarks):
                state.pose_counter += 1
            else:
                state.pose_counter = max(0, state.pose_counter - 1)

            if state.pose_counter >= POSE_CONFIRM_FRAMES:
                features = extract_base_features(normalized_exercise, landmarks)
                features = match_feature_dim(features, model_config.feature_dim)
                state.sequence.append(features)

                if len(state.sequence) == state.sequence_length:
                    seq = np.array(state.sequence, dtype=np.float32).reshape(
                        1, state.sequence_length, model_config.feature_dim
                    )
                    pred_raw = model.predict(seq, verbose=0)
                    pred_incorrect = parse_prediction_probability(pred_raw)
                    pred_incorrect = float(np.clip(pred_incorrect, 0.0, 1.0))

                    state.pred_buffer.append(pred_incorrect)
                    smooth_pred = float(np.mean(state.pred_buffer))
                    current_angles = state.sequence[-1]

                    if smooth_pred > 0.5:
                        label = "Incorrect"
                        confidence = smooth_pred
                        feedback = get_posture_feedback(normalized_exercise, current_angles, landmarks)
                    else:
                        label = "Correct"
                        confidence = 1 - smooth_pred
                        feedback = "Great form! Keep going!"
                else:
                    label = "Analyzing..."
                    feedback = "Hold position and keep moving naturally."
            else:
                label = f"Get into {normalized_exercise} position"
                feedback = "Align your body so the full pose is visible."

        elif normalized_exercise == "plank":
            label, confidence, feedback = predict_plank(model_config, results.pose_landmarks.landmark)

        elif normalized_exercise == "bicep":
            label, confidence, feedback = predict_bicep(model_config, results.pose_landmarks.landmark)

        else:
            label = "Unsupported exercise"
            confidence = 0.0
            feedback = "Choose a supported exercise."
    else:
        label = "No Pose Detected"
        feedback = "Make sure your full body is visible."

    return {
        "exercise": normalized_exercise,
        "prediction": label,
        "probability": round(confidence, 3),
        "feedback": feedback,
    }


@app.post("/reset")
def reset(exercise: str = Query(default="all")):
    normalized_exercise = normalize_exercise_name(exercise)
    if exercise.strip().lower() == "all":
        for state in exercise_states.values():
            state.clear()
        return {"status": "all buffers reset"}

    if not normalized_exercise:
        raise HTTPException(
            status_code=400,
            detail="Invalid exercise for reset. Use an exercise name or 'all'.",
        )

    exercise_states[normalized_exercise].clear()
    return {"status": f"buffer reset for {normalized_exercise}"}