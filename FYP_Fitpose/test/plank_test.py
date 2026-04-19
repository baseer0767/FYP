"""
Plank Form Detection — Real-time video test
=============================================
Errors detected (from Exercise-Correction plank model):

  1. Low back  → model predicts "L" with high confidence
  2. High back → model predicts "H" with high confidence

Edge-triggered: an error is only counted when the stage *transitions*
from correct to an error state (not every frame).

Plank is timed, not rep-counted — the HUD shows hold duration.
Press 'q' to quit the live window.
"""

import warnings
warnings.filterwarnings("ignore", category=UserWarning)

import cv2
import time
import numpy as np
import pandas as pd
import pickle
import mediapipe as mp

# ===============================
# CONFIGURATION
# ===============================
import os
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(BASE_DIR)
PLANK_MODEL_PATH  = os.path.join(PROJECT_ROOT, "models", "plank_model.pkl")
PLANK_SCALER_PATH = os.path.join(PROJECT_ROOT, "models", "plank_input_scaler.pkl")

# Video path (set to None or 0 for webcam)
import sys
VIDEO_PATH = sys.argv[1] if len(sys.argv) > 1 else os.path.join(PROJECT_ROOT, "Deadlift", "Correct", "plank.mp4")

# Thresholds
PREDICTION_PROBABILITY_THRESHOLD = 0.6

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
# LOAD PLANK MODEL
# ===============================
with open(PLANK_MODEL_PATH, "rb") as f:
    plank_model = pickle.load(f)
with open(PLANK_SCALER_PATH, "rb") as f:
    plank_scaler = pickle.load(f)

IMPORTANT_LANDMARKS = [
    "NOSE",
    "LEFT_SHOULDER",  "RIGHT_SHOULDER",
    "LEFT_ELBOW",     "RIGHT_ELBOW",
    "LEFT_WRIST",     "RIGHT_WRIST",
    "LEFT_HIP",       "RIGHT_HIP",
    "LEFT_KNEE",      "RIGHT_KNEE",
    "LEFT_ANKLE",     "RIGHT_ANKLE",
    "LEFT_HEEL",      "RIGHT_HEEL",
    "LEFT_FOOT_INDEX","RIGHT_FOOT_INDEX",
]

# Build column headers (must match training data format)
HEADERS = []
for lm in IMPORTANT_LANDMARKS:
    HEADERS += [f"{lm.lower()}_x", f"{lm.lower()}_y", f"{lm.lower()}_z", f"{lm.lower()}_v"]

print("Plank model loaded successfully")

# ===============================
# UTILITY FUNCTIONS
# ===============================
def extract_important_keypoints(mp_results):
    """Flat list of (x, y, z, visibility) for important landmarks."""
    row = []
    for name in IMPORTANT_LANDMARKS:
        lm = mp_results.pose_landmarks.landmark[mp_pose.PoseLandmark[name].value]
        row.extend([lm.x, lm.y, lm.z, lm.visibility])
    return row

# ===============================
# STATE
# ===============================
previous_stage = "unknown"
low_back_count  = 0
high_back_count = 0
hold_start_time = None   # tracks when plank hold began

# ===============================
# VIDEO SETUP
# ===============================
cap = cv2.VideoCapture(VIDEO_PATH if VIDEO_PATH else 0)
cv2.namedWindow("Plank Detection", cv2.WINDOW_NORMAL)
cv2.resizeWindow("Plank Detection", 1280, 720)

print("Plank detection started. Press 'q' to quit.")

# ===============================
# MAIN LOOP
# ===============================
while cap.isOpened():
    ret, frame = cap.read()
    if not ret:
        print("End of video.")
        break

    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    results = pose.process(rgb)

    main_text     = ""
    feedback_text = ""
    text_color    = (255, 255, 255)
    has_error     = False

    if results.pose_landmarks:
        # --- classify posture ---
        row = extract_important_keypoints(results)
        X = pd.DataFrame([row], columns=HEADERS)
        X = pd.DataFrame(plank_scaler.transform(X))

        predicted_class = plank_model.predict(X)[0]
        proba = plank_model.predict_proba(X)[0]
        confidence = round(proba[proba.argmax()], 2)

        # determine current stage
        if predicted_class == "C" and confidence >= PREDICTION_PROBABILITY_THRESHOLD:
            current_stage = "correct"
        elif predicted_class == "L" and confidence >= PREDICTION_PROBABILITY_THRESHOLD:
            current_stage = "low back"
        elif predicted_class == "H" and confidence >= PREDICTION_PROBABILITY_THRESHOLD:
            current_stage = "high back"
        else:
            current_stage = "unknown"

        # edge-triggered error counting
        if current_stage in ("low back", "high back"):
            has_error = True
            if previous_stage != current_stage:
                if current_stage == "low back":
                    low_back_count += 1
                else:
                    high_back_count += 1
        else:
            has_error = False

        previous_stage = current_stage

        # track hold time (start when first correct detection, pause on no-pose)
        if current_stage != "unknown" and hold_start_time is None:
            hold_start_time = time.time()

        # --- draw skeleton ---
        lm_color  = (0, 0, 255) if has_error else (0, 255, 0)
        con_color = (0, 0, 200) if has_error else (0, 200, 0)
        mp_drawing.draw_landmarks(
            frame, results.pose_landmarks, mp_pose.POSE_CONNECTIONS,
            mp_drawing.DrawingSpec(color=lm_color,  thickness=2, circle_radius=3),
            mp_drawing.DrawingSpec(color=con_color, thickness=2),
        )

        # --- overlay text ---
        elapsed = int(time.time() - hold_start_time) if hold_start_time else 0
        mins, secs = divmod(elapsed, 60)
        main_text = f"Hold: {mins:02d}:{secs:02d}  Stage: {current_stage}  Conf: {confidence}"

        if has_error:
            text_color = (0, 0, 255)
            feedback_text = f"{'LOW BACK — drop hips down!' if current_stage == 'low back' else 'HIGH BACK — raise hips up!'}"
        else:
            text_color = (0, 255, 0)
            feedback_text = "Good form! Hold steady."

    else:
        main_text = "No Pose Detected"
        feedback_text = "Make sure full body is visible"
        text_color = (0, 0, 255)

    # ===============================
    # HUD OVERLAY
    # ===============================
    h, w = frame.shape[:2]

    overlay = frame.copy()
    cv2.rectangle(overlay, (0, 0), (w, 100), (0, 0, 0), -1)
    cv2.addWeighted(overlay, 0.45, frame, 0.55, 0, frame)

    cv2.putText(frame, main_text,     (15, 35), cv2.FONT_HERSHEY_DUPLEX,  0.85, (255, 255, 255), 2)
    cv2.putText(frame, feedback_text, (15, 75), cv2.FONT_HERSHEY_SIMPLEX, 0.75, text_color, 2)

    # bottom-left error tally
    y0 = h - 60
    cv2.putText(frame, f"Low back errors: {low_back_count}",  (10, y0),      cv2.FONT_HERSHEY_SIMPLEX, 0.55, (200,200,200), 1)
    cv2.putText(frame, f"High back errors: {high_back_count}", (10, y0 + 25), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (200,200,200), 1)

    cv2.imshow("Plank Detection", frame)
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

# ===============================
# CLEANUP & SUMMARY
# ===============================
cap.release()
cv2.destroyAllWindows()
pose.close()

elapsed = int(time.time() - hold_start_time) if hold_start_time else 0
mins, secs = divmod(elapsed, 60)

print(f"\n=== Final Summary ===")
print(f"Hold time: {mins:02d}:{secs:02d}")
print(f"Low back errors:  {low_back_count}")
print(f"High back errors: {high_back_count}")
print("Detection stopped.")
