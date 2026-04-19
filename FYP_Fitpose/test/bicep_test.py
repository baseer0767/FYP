"""
Bicep Curl Form Detection — Real-time video test
==================================================
Mirrors the pushup pipeline (lstm_test.py) but uses the Exercise-Correction
bicep-curl error-detection logic:

  1. Lean too far back  → KNN model (bicep_curl_model.pkl + scaler)
  2. Loose upper arm    → ground-upper-arm angle > 40°
  3. Weak peak contract → bicep angle > 60° before arm comes down

Press 'q' to quit the live window.
"""

import warnings
warnings.filterwarnings("ignore", category=UserWarning)

import cv2
import numpy as np
import pickle
import mediapipe as mp

# ===============================
# CONFIGURATION
# ===============================
import os
# KNN lean-back model (now stored inside this repo)
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(BASE_DIR)
BICEP_MODEL_PATH  = os.path.join(PROJECT_ROOT, "models", "bicep_curl_model.pkl")
BICEP_SCALER_PATH = os.path.join(PROJECT_ROOT, "models", "bicep_curl_input_scaler.pkl")

# Video path (set to None or 0 for webcam)
VIDEO_PATH = os.path.join(PROJECT_ROOT, "Deadlift", "Correct", "bicep3.mp4")

# Thresholds  (same as Exercise-Correction defaults)
VISIBILITY_THRESHOLD            = 0.65
STAGE_UP_THRESHOLD              = 100   # elbow angle to count as "up"
STAGE_DOWN_THRESHOLD            = 120   # elbow angle to count as "down"
PEAK_CONTRACTION_THRESHOLD      = 60    # min contraction angle (error if higher)
LOOSE_UPPER_ARM_ANGLE_THRESHOLD = 40    # ground-upper-arm angle error
LEAN_BACK_CONFIDENCE            = 0.95  # KNN probability cutoff

# ===============================
# MEDIAPIPE INIT
# ===============================
mp_drawing = mp.solutions.drawing_utils
mp_pose    = mp.solutions.pose

pose = mp_pose.Pose(
    static_image_mode=False,
    model_complexity=1,
    min_detection_confidence=0.5,
    min_tracking_confidence=0.5,
)

# ===============================
# LOAD LEAN-BACK KNN MODEL
# ===============================
with open(BICEP_MODEL_PATH, "rb") as f:
    lean_back_model = pickle.load(f)
with open(BICEP_SCALER_PATH, "rb") as f:
    input_scaler = pickle.load(f)

IMPORTANT_LANDMARKS = [
    "NOSE",
    "LEFT_SHOULDER", "RIGHT_SHOULDER",
    "RIGHT_ELBOW",   "LEFT_ELBOW",
    "RIGHT_WRIST",   "LEFT_WRIST",
    "LEFT_HIP",      "RIGHT_HIP",
]

print("Model loaded successfully")

# ===============================
# UTILITY FUNCTIONS
# ===============================
def calculate_angle(a, b, c):
    """Angle in degrees at point b."""
    a, b, c = np.array(a, dtype=np.float64), np.array(b, dtype=np.float64), np.array(c, dtype=np.float64)
    ba = a - b
    bc = c - b
    cos = np.dot(ba, bc) / (np.linalg.norm(ba) * np.linalg.norm(bc) + 1e-6)
    return float(np.degrees(np.arccos(np.clip(cos, -1.0, 1.0))))


def extract_important_keypoints(mp_results):
    """Flat list of (x, y, z, v) for important landmarks."""
    row = []
    for name in IMPORTANT_LANDMARKS:
        lm = mp_results.pose_landmarks.landmark[mp_pose.PoseLandmark[name].value]
        row.extend([lm.x, lm.y, lm.z, lm.visibility])
    return row


def get_joint(landmarks, side, joint):
    idx = mp_pose.PoseLandmark[f"{side.upper()}_{joint}"].value
    lm = landmarks[idx]
    return [lm.x, lm.y], lm.visibility


# ===============================
# PER-ARM ANALYSIS STATE
# ===============================
class ArmState:
    def __init__(self, side):
        self.side = side
        self.counter = 0
        self.stage = "down"
        self.peak_contraction_angle = 1000
        self.loose_upper_arm_flag = False  # for edge-trigger (count once per event)
        self.errors = {"LOOSE_UPPER_ARM": 0, "PEAK_CONTRACTION": 0}

    def reset(self):
        self.counter = 0
        self.stage = "down"
        self.peak_contraction_angle = 1000
        self.loose_upper_arm_flag = False
        self.errors = {"LOOSE_UPPER_ARM": 0, "PEAK_CONTRACTION": 0}


left_arm  = ArmState("left")
right_arm = ArmState("right")

# Lean-back state
stand_posture          = 0
previous_stand_posture = 0
lean_back_count        = 0

# ===============================
# VIDEO SETUP
# ===============================
cap = cv2.VideoCapture(VIDEO_PATH if VIDEO_PATH else 0)
cv2.namedWindow("Bicep Curl Detection", cv2.WINDOW_NORMAL)
cv2.resizeWindow("Bicep Curl Detection", 1280, 720)

print("Bicep-curl detection started. Press 'q' to quit.")

# ===============================
# MAIN LOOP
# ===============================
while cap.isOpened():
    ret, frame = cap.read()
    if not ret:
        print("End of video.")
        break

    frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    results = pose.process(frame_rgb)

    # defaults for overlay
    main_text     = ""
    feedback_text = ""
    text_color    = (255, 255, 255)
    has_error     = False
    lean_back_error = False

    if results.pose_landmarks:
        landmarks = results.pose_landmarks.landmark

        # ---- Draw landmarks (green when OK, red when error — set later) ----
        # We draw after error evaluation so colour can change
        # (we'll redraw; MediaPipe draws in-place on the frame copy)

        # =============================================
        # 1. LEAN-BACK DETECTION  (KNN model)
        # =============================================
        row = extract_important_keypoints(results)
        X = np.array(row).reshape(1, -1)
        X = input_scaler.transform(X)
        predicted_class = lean_back_model.predict(X)[0]
        proba = lean_back_model.predict_proba(X)[0]
        confidence = round(proba[np.argmax(proba)], 2)

        if confidence >= LEAN_BACK_CONFIDENCE:
            stand_posture = predicted_class

        if stand_posture == "L":
            lean_back_error = True
            has_error = True
            if previous_stand_posture != stand_posture:
                lean_back_count += 1
        previous_stand_posture = stand_posture

        # =============================================
        # 2. PER-ARM ANALYSIS
        # =============================================
        for arm in (left_arm, right_arm):
            side = arm.side.upper()

            # visibility check
            sh_pt, sh_vis = get_joint(landmarks, arm.side, "SHOULDER")
            el_pt, el_vis = get_joint(landmarks, arm.side, "ELBOW")
            wr_pt, wr_vis = get_joint(landmarks, arm.side, "WRIST")

            if min(sh_vis, el_vis, wr_vis) < VISIBILITY_THRESHOLD:
                continue

            # bicep curl angle (wrist-elbow-shoulder)
            bicep_angle = calculate_angle(sh_pt, el_pt, wr_pt)

            # rep counting
            if bicep_angle > STAGE_DOWN_THRESHOLD:
                arm.stage = "down"
            elif bicep_angle < STAGE_UP_THRESHOLD and arm.stage == "down":
                arm.stage = "up"
                arm.counter += 1

            # ground-upper-arm angle (elbow, shoulder, shoulder projected down)
            shoulder_proj = [sh_pt[0], 1]
            ground_angle = calculate_angle(el_pt, sh_pt, shoulder_proj)

            # skip arm-error analysis when lean-back is active
            if lean_back_error:
                continue

            # --- LOOSE UPPER ARM ---
            if ground_angle > LOOSE_UPPER_ARM_ANGLE_THRESHOLD:
                has_error = True
                if not arm.loose_upper_arm_flag:
                    arm.loose_upper_arm_flag = True
                    arm.errors["LOOSE_UPPER_ARM"] += 1
            else:
                arm.loose_upper_arm_flag = False

            # --- PEAK CONTRACTION ---
            if arm.stage == "up" and bicep_angle < arm.peak_contraction_angle:
                arm.peak_contraction_angle = bicep_angle
            elif arm.stage == "down":
                if (arm.peak_contraction_angle != 1000
                        and arm.peak_contraction_angle >= PEAK_CONTRACTION_THRESHOLD):
                    has_error = True
                    arm.errors["PEAK_CONTRACTION"] += 1
                arm.peak_contraction_angle = 1000

        # ---- draw skeleton with colour based on error ----
        lm_color  = (0, 0, 255) if has_error else (0, 255, 0)
        con_color = (0, 0, 200) if has_error else (0, 200, 0)
        mp_drawing.draw_landmarks(
            frame, results.pose_landmarks, mp_pose.POSE_CONNECTIONS,
            mp_drawing.DrawingSpec(color=lm_color,  thickness=2, circle_radius=3),
            mp_drawing.DrawingSpec(color=con_color, thickness=2),
        )

        # ---- build overlay text ----
        left_reps  = left_arm.counter
        right_reps = right_arm.counter
        main_text = f"L:{left_reps}  R:{right_reps}"

        feedback_parts = []
        if lean_back_error:
            feedback_parts.append("LEAN TOO FAR BACK!")
        for arm in (left_arm, right_arm):
            if arm.loose_upper_arm_flag:
                feedback_parts.append(f"{arm.side.upper()} LOOSE UPPER ARM")
        # peak contraction feedback shown the frame it triggers
        # (but kept brief since it resets each rep)

        if has_error:
            text_color = (0, 0, 255)
            if not feedback_parts:
                feedback_parts.append("WEAK PEAK CONTRACTION")
            feedback_text = " | ".join(feedback_parts)
        else:
            text_color = (0, 255, 0)
            feedback_text = "Good form!"

    else:
        main_text = "No Pose Detected"
        feedback_text = "Make sure full body is visible"
        text_color = (0, 0, 255)

    # ===============================
    # HUD OVERLAY
    # ===============================
    h, w = frame.shape[:2]

    # semi-transparent dark bar at top
    overlay = frame.copy()
    cv2.rectangle(overlay, (0, 0), (w, 100), (0, 0, 0), -1)
    cv2.addWeighted(overlay, 0.45, frame, 0.55, 0, frame)

    # counters + errors summary line
    total_errors = (left_arm.errors["LOOSE_UPPER_ARM"]  + right_arm.errors["LOOSE_UPPER_ARM"]
                  + left_arm.errors["PEAK_CONTRACTION"] + right_arm.errors["PEAK_CONTRACTION"]
                  + lean_back_count)
    summary = f"Reps {main_text}   Errors:{total_errors}   LeanBack:{lean_back_count}"
    cv2.putText(frame, summary, (15, 30), cv2.FONT_HERSHEY_DUPLEX, 0.85, (255, 255, 255), 2)

    # feedback line
    cv2.putText(frame, feedback_text, (15, 70), cv2.FONT_HERSHEY_SIMPLEX, 0.8, text_color, 2)

    # bottom-left detailed error tally
    y0 = h - 90
    cv2.putText(frame, f"L arm errors: {left_arm.errors}",  (10, y0),      cv2.FONT_HERSHEY_SIMPLEX, 0.55, (200,200,200), 1)
    cv2.putText(frame, f"R arm errors: {right_arm.errors}", (10, y0 + 25), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (200,200,200), 1)
    cv2.putText(frame, f"Lean back: {lean_back_count}",     (10, y0 + 50), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (200,200,200), 1)

    cv2.imshow("Bicep Curl Detection", frame)
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

# ===============================
# CLEANUP & SUMMARY
# ===============================
cap.release()
cv2.destroyAllWindows()
pose.close()

print("\n=== Final Summary ===")
print(f"Left reps : {left_arm.counter}")
print(f"Right reps: {right_arm.counter}")
print(f"Left arm errors : {left_arm.errors}")
print(f"Right arm errors: {right_arm.errors}")
print(f"Lean back errors: {lean_back_count}")
print("Detection stopped.")
