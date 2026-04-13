import cv2
import numpy as np
import mediapipe as mp
from tensorflow.keras.models import load_model
from collections import deque
from pathlib import Path

# ===============================
# PARAMETERS
# ===============================
PROJECT_ROOT = Path(__file__).resolve().parent.parent
MODEL_PATH = PROJECT_ROOT / "models" / "deadlift_lstm_model.h5"
SEQUENCE_LENGTH = 30
NUM_ANGLES = 9
PRED_BUFFER = 5
POSE_CONFIRM_FRAMES = 8

VIDEO_PATH = PROJECT_ROOT / "Deadlift" / "Incorrect" / "2.mov"
# VIDEO_PATH = None

# ===============================
# LOAD MODEL
# ===============================
if not MODEL_PATH.exists():
    raise FileNotFoundError(f"Model file not found: {MODEL_PATH}")

model = load_model(str(MODEL_PATH))
print("✅ Deadlift model loaded")

# ===============================
# MEDIAPIPE INIT
# ===============================
mp_drawing = mp.solutions.drawing_utils
mp_pose = mp.solutions.pose

pose = mp_pose.Pose(
    static_image_mode=False,
    model_complexity=1,
    min_detection_confidence=0.5,
    min_tracking_confidence=0.5
)

# ===============================
# UTIL FUNCTIONS
# ===============================
def normalize_landmarks(frame):
    hip_center = (frame[23] + frame[24]) / 2
    return frame - hip_center

def calculate_angle(a, b, c):
    ba = a - b
    bc = c - b
    cosine = np.dot(ba, bc) / (np.linalg.norm(ba) * np.linalg.norm(bc) + 1e-6)
    return np.degrees(np.arccos(np.clip(cosine, -1.0, 1.0)))

def extract_angles(frame_landmarks):
    frame = normalize_landmarks(frame_landmarks)

    angles = [
        calculate_angle(frame[11], frame[23], frame[25]),
        calculate_angle(frame[12], frame[24], frame[26]),
        calculate_angle(frame[23], frame[25], frame[27]),
        calculate_angle(frame[24], frame[26], frame[28]),
        calculate_angle(frame[7], frame[11], frame[23]),
        calculate_angle(frame[8], frame[12], frame[24]),
        calculate_angle(frame[13], frame[11], frame[23]),
        calculate_angle(frame[14], frame[12], frame[24])
    ]

    hip_height = (frame[23][1] + frame[24][1]) / 2
    angles.append(hip_height)

    return np.array(angles)

# ===============================
# DEADLIFT POSTURE FEEDBACK
# ===============================
def get_deadlift_feedback(angles, landmarks):
    feedback = []

    hip_angle = np.mean(angles[0:2])
    knee_angle = np.mean(angles[2:4])
    back_angle = np.mean(angles[4:6])
    shoulder_angle = np.mean(angles[6:8])

    # Hip hinge check
    if hip_angle < 140:
        feedback.append("Hips too low — this is turning into a squat")

    if hip_angle > 200:
        feedback.append("Hips too high — bend more at knees")

    # Knee position
    if knee_angle < 140:
        feedback.append("Knees too bent — reduce squat movement")

    if knee_angle > 180:
        feedback.append("Slightly bend knees — avoid stiff legs")

    # Back posture (MOST IMPORTANT)
    if back_angle < 150:
        feedback.append("Keep your back straight — avoid rounding")

    # Shoulder alignment
    shoulder_x = (landmarks[11][0] + landmarks[12][0]) / 2
    hip_x = (landmarks[23][0] + landmarks[24][0]) / 2

    if abs(shoulder_x - hip_x) > 0.1:
        feedback.append("Keep bar close — shoulders over hips")

    if not feedback:
        feedback.append("Good form — controlled movement")

    return " | ".join(feedback[:2])

# ===============================
# DEADLIFT POSE VALIDATION
# ===============================
def is_deadlift_pose(landmarks):
    shoulder_y = (landmarks[11][1] + landmarks[12][1]) / 2
    hip_y = (landmarks[23][1] + landmarks[24][1]) / 2
    knee_y = (landmarks[25][1] + landmarks[26][1]) / 2

    # Check vertical alignment (hinge posture)
    if not (shoulder_y < hip_y < knee_y):
        return False

    # Basic angle sanity
    left_knee = calculate_angle(landmarks[23], landmarks[25], landmarks[27])
    right_knee = calculate_angle(landmarks[24], landmarks[26], landmarks[28])

    if left_knee < 120 or right_knee < 120:
        return False

    return True

# ===============================
# VIDEO SETUP
# ===============================
video_source = str(VIDEO_PATH) if VIDEO_PATH else 0
cap = cv2.VideoCapture(video_source)

cv2.namedWindow("Deadlift Form Detection", cv2.WINDOW_NORMAL)
cv2.resizeWindow("Deadlift Form Detection", 1280, 720)

sequence_buffer = deque(maxlen=SEQUENCE_LENGTH)
pred_buffer = deque(maxlen=PRED_BUFFER)
pose_valid_counter = 0

print("🚀 Deadlift detection started")

# ===============================
# MAIN LOOP
# ===============================
while cap.isOpened():
    ret, frame = cap.read()
    if not ret:
        break

    frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    results = pose.process(frame_rgb)

    main_text = ""
    feedback_text = ""
    text_color = (255, 255, 255)

    if results.pose_landmarks:
        mp_drawing.draw_landmarks(
            frame,
            results.pose_landmarks,
            mp_pose.POSE_CONNECTIONS
        )

        landmarks = np.array([[lm.x, lm.y, lm.z] for lm in results.pose_landmarks.landmark])

        if is_deadlift_pose(landmarks):
            pose_valid_counter += 1
        else:
            pose_valid_counter = max(0, pose_valid_counter - 1)

        if pose_valid_counter >= POSE_CONFIRM_FRAMES:
            angles = extract_angles(landmarks)
            sequence_buffer.append(angles)

            if len(sequence_buffer) == SEQUENCE_LENGTH:
                input_seq = np.array(sequence_buffer).reshape(1, SEQUENCE_LENGTH, NUM_ANGLES)

                pred = model.predict(input_seq, verbose=0)[0][0]
                pred_buffer.append(pred)
                smooth_pred = np.mean(pred_buffer)

                label = "Incorrect" if smooth_pred > 0.5 else "Correct"
                confidence = smooth_pred if label == "Incorrect" else (1 - smooth_pred)

                text_color = (0, 0, 255) if label == "Incorrect" else (0, 255, 0)
                main_text = f"Deadlift: {label} ({confidence:.2%})"

                if label == "Incorrect":
                    feedback_text = get_deadlift_feedback(angles, landmarks)
                else:
                    feedback_text = "Excellent form — keep going!"
            else:
                main_text = "Analyzing..."
                feedback_text = "Hold position"
                text_color = (255, 255, 0)
        else:
            main_text = "Get into deadlift position"
            feedback_text = "Stand side view, full body visible"
            text_color = (0, 255, 255)

    else:
        pose_valid_counter = 0
        sequence_buffer.clear()
        pred_buffer.clear()
        main_text = "No Pose Detected"
        feedback_text = "Ensure full body is visible"
        text_color = (0, 0, 255)

    # ===============================
    # DISPLAY TEXT (WRAPPED)
    # ===============================
    cv2.putText(frame, main_text, (30, 60),
                cv2.FONT_HERSHEY_DUPLEX, 1.2, text_color, 3)

    # Wrap feedback
    words = feedback_text.split(" ")
    lines, current = [], ""

    for word in words:
        test = current + (" " + word if current else word)
        (w, _), _ = cv2.getTextSize(test, cv2.FONT_HERSHEY_SIMPLEX, 0.8, 2)
        if w < frame.shape[1] - 60:
            current = test
        else:
            lines.append(current)
            current = word
    if current:
        lines.append(current)

    overlay = frame.copy()
    cv2.rectangle(overlay, (10, 80), (frame.shape[1]-10, 160 + len(lines)*30), (0,0,0), -1)
    cv2.addWeighted(overlay, 0.4, frame, 0.6, 0, frame)

    for i, line in enumerate(lines[:3]):
        cv2.putText(frame, line, (30, 120 + i*30),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.8, text_color, 2)

    cv2.imshow("Deadlift Form Detection", frame)

    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()
pose.close()
print("👋 Done")