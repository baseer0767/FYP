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
    "pushup": "pushup_lstm_10f_stride_5.h5",
    "deadlift": "deadlift_lstm_model_1.h5",
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
POSE_CONFIRM_FRAMES = 3
PLANK_CONFIDENCE_THRESHOLD = 0.6
BICEP_CONFIDENCE_THRESHOLD = 0.95
BICEP_VISIBILITY_THRESHOLD = 0.65
BICEP_STAGE_UP_THRESHOLD = 100
BICEP_STAGE_DOWN_THRESHOLD = 120
BICEP_PEAK_CONTRACTION_THRESHOLD = 60
BICEP_LOOSE_UPPER_ARM_ANGLE_THRESHOLD = 40
MAX_PROCESS_WIDTH = 480

PUSHUP_SEQUENCE_LENGTH = 10
PUSHUP_PRED_BUFFER = 8
PUSHUP_POSE_CONFIRM_FRAMES = 4
PUSHUP_THRESHOLD = 0.7
PUSHUP_BIAS = 0.12

DEADLIFT_SEQUENCE_LENGTH = 10
DEADLIFT_PRED_BUFFER = 4
DEADLIFT_POSE_CONFIRM_FRAMES = 2
DEADLIFT_MIN_SEQUENCE_FOR_PRED = 5
DEADLIFT_THRESHOLD = 0.7
DEADLIFT_BIAS = 0.12
DEADLIFT_CORRECT_MARGIN = 0.06
DEADLIFT_MIN_MOTION_SCORE = 0.9
DEADLIFT_IDLE_HIP_ANGLE_MIN = 170
DEADLIFT_IDLE_KNEE_ANGLE_MIN = 168
DEADLIFT_IDLE_HINGE_OFFSET_MAX = 0.04
DEADLIFT_BACKBEND_HIP_ANGLE_MIN = 160
DEADLIFT_BACKBEND_KNEE_ANGLE_MIN = 150
DEADLIFT_BACKBEND_TORSO_OFFSET_MIN = 0.05
DEADLIFT_BACKBEND_FEMUR_OFFSET_MIN = 0.03
DEADLIFT_ROUNDED_BACK_ANGLE_MAX = 152
DEADLIFT_KNEE_TOO_BENT_MAX = 138
DEADLIFT_KNEE_TOO_STRAIGHT_MIN = 182
DEADLIFT_HIP_TOO_LOW_MAX = 138
DEADLIFT_HIP_TOO_HIGH_MIN = 200
DEADLIFT_BAR_PATH_OFFSET_MAX = 0.12

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
                seq_len = PUSHUP_SEQUENCE_LENGTH
                feat_dim = int(input_shape[2]) if input_shape and input_shape[2] else 8
            elif exercise == "deadlift":
                seq_len = int(input_shape[1]) if input_shape and input_shape[1] else DEADLIFT_SEQUENCE_LENGTH
                feat_dim = int(input_shape[2]) if input_shape and input_shape[2] else 9
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
    model_complexity=0,
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
    a = np.asarray(a, dtype=np.float32)
    b = np.asarray(b, dtype=np.float32)
    c = np.asarray(c, dtype=np.float32)
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


def get_joint_point_and_visibility(landmarks, side: str, joint: str):
    idx = mp_pose.PoseLandmark[f"{side.upper()}_{joint}"].value
    lm = landmarks[idx]
    return [lm.x, lm.y], lm.visibility


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


def predict_bicep(model_config: ModelConfig, landmarks, bicep_state):
    row = extract_important_keypoints(landmarks, BICEP_LANDMARKS)
    X = row.reshape(1, -1)
    if model_config.scaler is not None:
        feature_names = getattr(model_config.scaler, "feature_names_in_", None)
        if feature_names is not None:
            X = model_config.scaler.transform(pd.DataFrame(X, columns=feature_names))
        else:
            X = model_config.scaler.transform(X)

    predicted_class = model_config.model.predict(X)[0]
    proba = model_config.model.predict_proba(X)[0]
    confidence = float(round(proba[int(np.argmax(proba))], 2))

    if confidence >= BICEP_CONFIDENCE_THRESHOLD:
        bicep_state.stand_posture = predicted_class

    lean_back_error = bicep_state.stand_posture == "L"
    weak_peak_contraction = False

    for side, arm_state in (("left", bicep_state.left_arm), ("right", bicep_state.right_arm)):
        shoulder_pt, shoulder_vis = get_joint_point_and_visibility(landmarks, side, "SHOULDER")
        elbow_pt, elbow_vis = get_joint_point_and_visibility(landmarks, side, "ELBOW")
        wrist_pt, wrist_vis = get_joint_point_and_visibility(landmarks, side, "WRIST")

        if min(shoulder_vis, elbow_vis, wrist_vis) < BICEP_VISIBILITY_THRESHOLD:
            continue

        bicep_angle = calculate_angle(shoulder_pt, elbow_pt, wrist_pt)

        if bicep_angle > BICEP_STAGE_DOWN_THRESHOLD:
            arm_state.stage = "down"
        elif bicep_angle < BICEP_STAGE_UP_THRESHOLD and arm_state.stage == "down":
            arm_state.stage = "up"

        shoulder_proj = [shoulder_pt[0], 1]
        ground_angle = calculate_angle(elbow_pt, shoulder_pt, shoulder_proj)

        if lean_back_error:
            # Lean-back feedback has priority; keep per-arm flags from becoming stale.
            arm_state.loose_upper_arm_flag = False
            arm_state.peak_contraction_angle = 1000.0
            continue

        if ground_angle > BICEP_LOOSE_UPPER_ARM_ANGLE_THRESHOLD:
            arm_state.loose_upper_arm_flag = True
        else:
            arm_state.loose_upper_arm_flag = False

        if arm_state.stage == "up" and bicep_angle < arm_state.peak_contraction_angle:
            arm_state.peak_contraction_angle = bicep_angle
        elif arm_state.stage == "down":
            if (
                arm_state.peak_contraction_angle != 1000.0
                and arm_state.peak_contraction_angle >= BICEP_PEAK_CONTRACTION_THRESHOLD
            ):
                weak_peak_contraction = True
            arm_state.peak_contraction_angle = 1000.0

    if lean_back_error:
        return "Incorrect", confidence, "Lean too far back. Keep your torso upright."

    loose_sides = []
    if bicep_state.left_arm.loose_upper_arm_flag:
        loose_sides.append("left")
    if bicep_state.right_arm.loose_upper_arm_flag:
        loose_sides.append("right")

    if loose_sides:
        if len(loose_sides) == 2:
            return "Incorrect", confidence, "Loose upper arm on both sides. Keep elbows fixed."
        return "Incorrect", confidence, f"Loose upper arm on {loose_sides[0]} side. Keep elbow fixed."

    if weak_peak_contraction:
        return "Incorrect", confidence, "Weak peak contraction. Squeeze more at the top."

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


def is_deadlift_back_bend(angles, landmarks) -> bool:
    hip_angle = float(np.mean(angles[0:2]))
    knee_angle = float(np.mean(angles[2:4]))

    # Backward lean at lockout is meaningful only when hips and knees are near extension.
    if hip_angle < DEADLIFT_BACKBEND_HIP_ANGLE_MIN or knee_angle < DEADLIFT_BACKBEND_KNEE_ANGLE_MIN:
        return False

    shoulder_x = (landmarks[11][0] + landmarks[12][0]) / 2
    hip_x = (landmarks[23][0] + landmarks[24][0]) / 2
    knee_x = (landmarks[25][0] + landmarks[26][0]) / 2

    torso_lateral = shoulder_x - hip_x
    femur_lateral = knee_x - hip_x

    if abs(torso_lateral) < DEADLIFT_BACKBEND_TORSO_OFFSET_MIN:
        return False
    if abs(femur_lateral) < DEADLIFT_BACKBEND_FEMUR_OFFSET_MIN:
        return False

    # Opposite torso/femur horizontal directions indicate hyperextension (leaning back).
    return torso_lateral * femur_lateral < 0


def deadlift_form_issues(angles, landmarks):
    issues = []

    hip_angle = float(np.mean(angles[0:2]))
    knee_angle = float(np.mean(angles[2:4]))
    back_angle = float(np.mean(angles[4:6]))

    shoulder_x = (landmarks[11][0] + landmarks[12][0]) / 2
    hip_x = (landmarks[23][0] + landmarks[24][0]) / 2
    shoulder_hip_offset = abs(shoulder_x - hip_x)

    if is_deadlift_back_bend(angles, landmarks):
        issues.append("Backward lean detected. Keep ribs down and finish tall.")

    if back_angle < DEADLIFT_ROUNDED_BACK_ANGLE_MAX:
        issues.append("Back is rounding. Keep your spine neutral and brace your core.")

    if knee_angle < DEADLIFT_KNEE_TOO_BENT_MAX:
        issues.append("Knees are too bent. Avoid turning the deadlift into a squat.")
    elif knee_angle > DEADLIFT_KNEE_TOO_STRAIGHT_MIN:
        issues.append("Knees are too straight. Keep a slight bend to stay strong.")

    if hip_angle < DEADLIFT_HIP_TOO_LOW_MAX:
        issues.append("Hips are too low. Start with a stronger hip hinge.")
    elif hip_angle > DEADLIFT_HIP_TOO_HIGH_MIN:
        issues.append("Hips are too high. Sit back and load your legs.")

    if shoulder_hip_offset > DEADLIFT_BAR_PATH_OFFSET_MAX:
        issues.append("Keep the bar path close to your body.")

    return issues


def get_posture_feedback(exercise: str, angles, landmarks):
    if exercise == "deadlift":
        feedback = deadlift_form_issues(angles, landmarks)

        if not feedback:
            feedback.append("Good form. Keep the movement controlled.")

        return " | ".join(feedback[:2])

    if exercise != "pushup":
        return f"{exercise.capitalize()} posture needs adjustment. Keep your form controlled."

    feedback = []
    avg_elbow = np.mean(angles[0:2])
    avg_shoulder = np.mean(angles[2:4])
    avg_hip = np.mean(angles[4:6])
    avg_knee = np.mean(angles[6:8])

    if avg_hip < 155:
        feedback.append("Raise your hips! Keep your body in a straight line.")
    if avg_hip > 190:
        feedback.append("Lower your hips! Avoid piking.")
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
        feedback.append("Good effort! Minor adjustments needed.")

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


def is_deadlift_pose(landmarks):
    shoulder_y = (landmarks[11][1] + landmarks[12][1]) / 2
    hip_y = (landmarks[23][1] + landmarks[24][1]) / 2
    knee_y = (landmarks[25][1] + landmarks[26][1]) / 2
    ankle_y = (landmarks[27][1] + landmarks[28][1]) / 2

    if not (shoulder_y < hip_y < knee_y < ankle_y):
        return False

    left_hip = calculate_angle(landmarks[11], landmarks[23], landmarks[25])
    right_hip = calculate_angle(landmarks[12], landmarks[24], landmarks[26])
    left_knee = calculate_angle(landmarks[23], landmarks[25], landmarks[27])
    right_knee = calculate_angle(landmarks[24], landmarks[26], landmarks[28])

    avg_hip = (left_hip + right_hip) / 2
    avg_knee = (left_knee + right_knee) / 2

    shoulder_x = (landmarks[11][0] + landmarks[12][0]) / 2
    hip_x = (landmarks[23][0] + landmarks[24][0]) / 2
    hinge_offset = abs(shoulder_x - hip_x)

    # Reject upright idle stance where user is visible but not in deadlift mechanics.
    if (
        avg_hip > DEADLIFT_IDLE_HIP_ANGLE_MIN
        and avg_knee > DEADLIFT_IDLE_KNEE_ANGLE_MIN
        and hinge_offset < DEADLIFT_IDLE_HINGE_OFFSET_MAX
    ):
        return False

    return 90 < avg_hip < 220 and 110 < avg_knee < 195


def deadlift_motion_score(sequence: deque) -> float:
    if len(sequence) < 2:
        return 0.0

    seq_arr = np.array(sequence, dtype=np.float32)
    return float(np.mean(np.abs(np.diff(seq_arr, axis=0))))


def is_pose_valid(exercise: str, landmarks):
    if exercise == "pushup":
        return is_pushup_pose(landmarks)
    if exercise == "deadlift":
        return is_deadlift_pose(landmarks)
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


def downscale_for_pose(frame: np.ndarray, max_width: int = MAX_PROCESS_WIDTH) -> np.ndarray:
    height, width = frame.shape[:2]
    if width <= max_width:
        return frame

    scale = max_width / float(width)
    target_height = max(1, int(height * scale))
    return cv2.resize(frame, (max_width, target_height), interpolation=cv2.INTER_AREA)


# =============================
# STATE (PER-EXERCISE BUFFER)
# =============================
class SequenceState:
    def __init__(self, sequence_length: int, pred_buffer_size: int = PRED_BUFFER):
        self.sequence_length = sequence_length
        self.sequence = deque(maxlen=sequence_length)
        self.pred_buffer = deque(maxlen=pred_buffer_size)
        self.pose_counter = 0

    def clear(self):
        self.sequence.clear()
        self.pred_buffer.clear()
        self.pose_counter = 0


class BicepArmState:
    def __init__(self):
        self.stage = "down"
        self.peak_contraction_angle = 1000.0
        self.loose_upper_arm_flag = False

    def clear(self):
        self.stage = "down"
        self.peak_contraction_angle = 1000.0
        self.loose_upper_arm_flag = False


class BicepRuntimeState:
    def __init__(self):
        self.stand_posture = 0
        self.left_arm = BicepArmState()
        self.right_arm = BicepArmState()

    def clear(self):
        self.stand_posture = 0
        self.left_arm.clear()
        self.right_arm.clear()


exercise_states = {}
for name, cfg in models.items():
    if name == "pushup":
        exercise_states[name] = SequenceState(PUSHUP_SEQUENCE_LENGTH, PUSHUP_PRED_BUFFER)
    elif name == "deadlift":
        exercise_states[name] = SequenceState(cfg.sequence_length, DEADLIFT_PRED_BUFFER)
    else:
        exercise_states[name] = SequenceState(cfg.sequence_length)

bicep_runtime_state = BicepRuntimeState()


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

    frame = downscale_for_pose(frame)

    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    results = pose.process(rgb)

    label = "Processing"
    confidence = 0.0
    feedback = "Analyzing posture..."

    if results.pose_landmarks:
        landmarks = np.array([[lm.x, lm.y, lm.z] for lm in results.pose_landmarks.landmark])

        if normalized_exercise in ("pushup", "deadlift"):
            state = exercise_states[normalized_exercise]

            pose_ok = is_pose_valid(normalized_exercise, landmarks)

            if pose_ok:
                state.pose_counter += 1
            else:
                state.pose_counter = max(0, state.pose_counter - 1)
                if normalized_exercise == "deadlift" and state.pose_counter == 0:
                    state.sequence.clear()
                    state.pred_buffer.clear()

            if normalized_exercise == "pushup":
                required_pose_frames = PUSHUP_POSE_CONFIRM_FRAMES
            else:
                required_pose_frames = DEADLIFT_POSE_CONFIRM_FRAMES

            if state.pose_counter >= required_pose_frames:
                features = extract_base_features(normalized_exercise, landmarks)
                features = match_feature_dim(features, model_config.feature_dim)
                state.sequence.append(features)

                deadlift_can_predict_early = (
                    normalized_exercise == "deadlift"
                    and len(state.sequence) >= DEADLIFT_MIN_SEQUENCE_FOR_PRED
                )

                if len(state.sequence) == state.sequence_length or deadlift_can_predict_early:
                    if normalized_exercise == "pushup":
                        seq = np.array(state.sequence, dtype=np.float32).reshape(
                            1, state.sequence_length, model_config.feature_dim
                        )
                        pred_raw = model.predict(seq, verbose=0, batch_size=1)
                        pred_incorrect = parse_prediction_probability(pred_raw)
                        pred_incorrect = float(np.clip(pred_incorrect, 0.0, 1.0))

                        state.pred_buffer.append(pred_incorrect)
                        smooth_pred = float(np.mean(state.pred_buffer))
                        current_angles = state.sequence[-1]

                        adjusted_pred = max(0.0, smooth_pred - PUSHUP_BIAS)
                        if adjusted_pred < PUSHUP_THRESHOLD:
                            label = "Correct"
                            confidence = 1 - adjusted_pred
                            feedback = "Perfect form! Keep it up!"
                        else:
                            label = "Incorrect"
                            confidence = adjusted_pred
                            feedback = get_posture_feedback(normalized_exercise, current_angles, landmarks)
                    else:
                        motion_score = deadlift_motion_score(state.sequence)
                        if motion_score < DEADLIFT_MIN_MOTION_SCORE:
                            label = "Get into deadlift position"
                            confidence = 0.0
                            feedback = "Start deadlift movement. Standing still cannot be scored."
                            state.pred_buffer.clear()
                        else:
                            seq_frames = np.array(state.sequence, dtype=np.float32)
                            if seq_frames.shape[0] < state.sequence_length:
                                pad_count = state.sequence_length - seq_frames.shape[0]
                                pad_frames = np.repeat(seq_frames[-1:, :], pad_count, axis=0)
                                seq_frames = np.concatenate([seq_frames, pad_frames], axis=0)

                            seq = seq_frames.reshape(
                                1, state.sequence_length, model_config.feature_dim
                            )
                            pred_raw = model.predict(seq, verbose=0, batch_size=1)
                            pred_incorrect = parse_prediction_probability(pred_raw)
                            pred_incorrect = float(np.clip(pred_incorrect, 0.0, 1.0))

                            state.pred_buffer.append(pred_incorrect)
                            smooth_pred = float(np.mean(state.pred_buffer))
                            current_angles = state.sequence[-1]
                            form_issues = deadlift_form_issues(current_angles, landmarks)

                            adjusted_pred = min(1.0, smooth_pred + DEADLIFT_BIAS)
                            deadlift_correct_cutoff = max(0.0, DEADLIFT_THRESHOLD - DEADLIFT_CORRECT_MARGIN)

                            if form_issues:
                                label = "Incorrect"
                                confidence = max(adjusted_pred, DEADLIFT_THRESHOLD)
                                feedback = " | ".join(form_issues[:2])
                            elif len(state.sequence) < state.sequence_length:
                                label = "Analyzing..."
                                confidence = float(max(0.0, min(1.0, (1 - adjusted_pred) * 0.7)))
                                feedback = (
                                    f"Stabilizing sequence ({len(state.sequence)}/{state.sequence_length}). "
                                    "Keep the same form for confirmation."
                                )
                            elif adjusted_pred < deadlift_correct_cutoff:
                                label = "Correct"
                                confidence = 1 - adjusted_pred
                                feedback = "Perfect form! Keep it up!"
                            elif adjusted_pred < DEADLIFT_THRESHOLD:
                                label = "Analyzing..."
                                confidence = float(max(0.0, min(1.0, (1 - adjusted_pred) * 0.8)))
                                feedback = "Keep form consistent for confirmation."
                            else:
                                label = "Incorrect"
                                confidence = adjusted_pred
                                feedback = get_posture_feedback(normalized_exercise, current_angles, landmarks)
                else:
                    label = "Analyzing..."
                    feedback = f"Collecting sequence ({len(state.sequence)}/{state.sequence_length})"
            else:
                label = f"Get into {normalized_exercise} position"
                if normalized_exercise == "deadlift":
                    feedback = "Stand sideways and start a hip-hinge movement with full body visible."
                else:
                    feedback = "Align your body so the full pose is visible."

        elif normalized_exercise == "plank":
            label, confidence, feedback = predict_plank(model_config, results.pose_landmarks.landmark)

        elif normalized_exercise == "bicep":
            label, confidence, feedback = predict_bicep(
                model_config,
                results.pose_landmarks.landmark,
                bicep_runtime_state,
            )

        else:
            label = "Unsupported exercise"
            confidence = 0.0
            feedback = "Choose a supported exercise."
    else:
        if normalized_exercise == "deadlift":
            exercise_states[normalized_exercise].clear()
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
        bicep_runtime_state.clear()
        return {"status": "all buffers reset"}

    if not normalized_exercise:
        raise HTTPException(
            status_code=400,
            detail="Invalid exercise for reset. Use an exercise name or 'all'.",
        )

    exercise_states[normalized_exercise].clear()
    if normalized_exercise == "bicep":
        bicep_runtime_state.clear()
    return {"status": f"buffer reset for {normalized_exercise}"}