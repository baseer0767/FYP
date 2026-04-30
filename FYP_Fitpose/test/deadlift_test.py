import cv2
import ctypes
import numpy as np
import mediapipe as mp
from tensorflow.keras.models import load_model
from collections import deque
from pathlib import Path
import joblib

# ===============================
# PARAMETERS
# ===============================
PROJECT_ROOT = Path(__file__).resolve().parent.parent
MODEL_PATH = PROJECT_ROOT / "models" / "deadlift_lstm_model_20f_v2.h5"
SCALER_PATH = PROJECT_ROOT / "models" / "deadlift_scaler.save"

SEQUENCE_LENGTH = 20
NUM_FEATURES = 15

VIDEO_PATH = None                    # Set path for testing video
#VIDEO_PATH = PROJECT_ROOT / "Deadlift" / "Correct" / "2.mov"
MOVEMENT_THRESHOLD = 0.2
POSE_CONFIRM_FRAMES = 8
PRED_THRESHOLD = 0.50                # Increased a bit (less strict on model)

WINDOW_NAME = "Deadlift Form Detection"

# Screen size
try:
    user32 = ctypes.windll.user32
    SCREEN_WIDTH = user32.GetSystemMetrics(0)
    SCREEN_HEIGHT = user32.GetSystemMetrics(1)
except:
    SCREEN_WIDTH, SCREEN_HEIGHT = 1280, 720

# ===============================
# LOAD MODEL + SCALER
# ===============================
model = load_model(str(MODEL_PATH))
scaler = joblib.load(str(SCALER_PATH))
print("✅ Model + Scaler loaded")

# ===============================
# MEDIAPIPE
# ===============================
mp_pose = mp.solutions.pose
mp_drawing = mp.solutions.drawing_utils

pose = mp_pose.Pose(min_detection_confidence=0.5, min_tracking_confidence=0.65)

# ===============================
# HELPERS
# ===============================
def normalize_landmarks(frame):
    return frame - (frame[23] + frame[24]) / 2


def calculate_angle(a, b, c):
    ba, bc = a - b, c - b
    norm = np.linalg.norm(ba) * np.linalg.norm(bc) + 1e-6
    cosine = np.dot(ba, bc) / norm
    return np.degrees(np.arccos(np.clip(cosine, -1.0, 1.0)))


def extract_features(landmarks, prev_vals):
    frame = normalize_landmarks(landmarks)

    l_hip = calculate_angle(frame[11], frame[23], frame[25])
    r_hip = calculate_angle(frame[12], frame[24], frame[26])
    l_knee = calculate_angle(frame[23], frame[25], frame[27])
    r_knee = calculate_angle(frame[24], frame[26], frame[28])
    l_torso = calculate_angle(frame[7], frame[11], frame[23])
    r_torso = calculate_angle(frame[8], frame[12], frame[24])

    hip_y = (frame[23][1] + frame[24][1]) / 2
    shoulder_y = (frame[11][1] + frame[12][1]) / 2

    if prev_vals is None:
        hip_v = shoulder_v = 0.0
    else:
        hip_v = hip_y - prev_vals[0]
        shoulder_v = shoulder_y - prev_vals[1]

    hip_sym = abs(l_hip - r_hip)
    knee_sym = abs(l_knee - r_knee)
    hand_x = (frame[15][0] + frame[16][0]) / 2
    hip_x = (frame[23][0] + frame[24][0]) / 2
    bar_offset = abs(hand_x - hip_x)

    mid_shoulder = (frame[11] + frame[12]) / 2
    mid_hip = (frame[23] + frame[24]) / 2
    mid_knee = (frame[25] + frame[26]) / 2
    spine_angle = calculate_angle(mid_shoulder, mid_hip, mid_knee)

    features = np.array([
        l_hip, r_hip, l_knee, r_knee, l_torso, r_torso,
        hip_y, hip_v, shoulder_v, hip_sym, knee_sym,
        bar_offset, spine_angle, abs(l_torso - r_torso), abs(l_hip - r_hip)
    ])

    return features, (hip_y, shoulder_y)


def calculate_movement(curr, prev):
    if prev is None:
        return 0.0
    return np.mean(np.abs(curr - prev))


# ===============================
# HIGHLY RELAXED RULE SYSTEM
# ===============================
def is_good_deadlift_form(features, landmarks):
    spine_angle = features[12]
    bar_offset = features[11]
    hip_angle = np.mean([features[0], features[1]])
    knee_angle = np.mean([features[2], features[3]])
    torso_angle = np.mean([features[4], features[5]])

    issues = []

    # 1. Back Rounding - Only flag significant rounding
    if spine_angle < 70:
        issues.append("Back rounding")

    # 2. Knee Bend - Only flag excessive bend
    if knee_angle < 85:
        issues.append("Too much knee bend")

    # 3. Hips Position - Only flag obvious problems
    if hip_angle > 200:
        issues.append("Hips too high")

    # 4. Bar Path
    if bar_offset > 0.16:                                  # More tolerant
        issues.append("Bar too far from body")

    is_good = len(issues) == 0
    feedback = " | ".join(issues[:2]) if issues else "Good form"

    return is_good, feedback


# ===============================
# VIDEO SETUP
# ===============================
source = 0 if VIDEO_PATH is None else str(VIDEO_PATH)
cap = cv2.VideoCapture(source)

cv2.namedWindow(WINDOW_NAME, cv2.WINDOW_NORMAL)

sequence = deque(maxlen=SEQUENCE_LENGTH)
prev_features = None
prev_vals = None
pose_counter = 0

print("🚀 Deadlift Detection Started - Rules Heavily Relaxed")

# ===============================
# MAIN LOOP
# ===============================
while cap.isOpened():
    ret, frame = cap.read()
    if not ret:
        break

    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    result = pose.process(rgb)

    text = ""
    feedback = ""
    color = (255, 255, 255)
    movement = 0.0
    confidence = 0.0

    if result.pose_landmarks:
        mp_drawing.draw_landmarks(frame, result.pose_landmarks, mp_pose.POSE_CONNECTIONS)
        lm = np.array([[p.x, p.y, p.z] for p in result.pose_landmarks.landmark])

        features, prev_vals = extract_features(lm, prev_vals)

        movement = calculate_movement(features, prev_features)
        prev_features = features.copy()

        if movement > MOVEMENT_THRESHOLD:
            pose_counter += 1
        else:
            pose_counter = max(0, pose_counter - 1)

        if pose_counter >= POSE_CONFIRM_FRAMES and len(sequence) < SEQUENCE_LENGTH:
            sequence.append(features)

        if len(sequence) == SEQUENCE_LENGTH and movement > MOVEMENT_THRESHOLD:
            seq_array = np.array(sequence)
            seq_scaled = scaler.transform(seq_array).reshape(1, SEQUENCE_LENGTH, NUM_FEATURES)

            pred = model.predict(seq_scaled, verbose=0)[0][0]   # Prob of being Incorrect
            confidence = 1 - pred

            form_ok, rule_feedback = is_good_deadlift_form(features, lm)

            # Final Hybrid Decision - Giving more weight to model now
            if pred < PRED_THRESHOLD and form_ok:
                text = f"✅ Correct ({confidence:.0%})"
                feedback = "Excellent form — keep going!"
                color = (0, 255, 0)
            else:
                text = "❌ Incorrect"
                feedback = rule_feedback if rule_feedback != "Good form" else "Form needs improvement"
                color = (0, 0, 255)
        else:
            text = "Get into deadlift position"
            feedback = "Side view • Start lifting"
            color = (0, 255, 255)

    else:
        text = "No Pose Detected"
        feedback = "Full body visible"
        color = (0, 0, 255)

    # Display
    cv2.putText(frame, text, (40, 70), cv2.FONT_HERSHEY_DUPLEX, 1.35, color, 3)
    cv2.putText(frame, feedback, (40, 125), cv2.FONT_HERSHEY_SIMPLEX, 0.9, color, 2)
    cv2.putText(frame, f"Mov: {movement:.3f} | Conf: {confidence:.2f}", 
                (40, 180), cv2.FONT_HERSHEY_SIMPLEX, 0.75, (200,200,200), 2)

    display_frame = cv2.resize(frame, (SCREEN_WIDTH, SCREEN_HEIGHT))
    cv2.imshow(WINDOW_NAME, display_frame)

    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()
pose.close()
print("👋 Session ended")