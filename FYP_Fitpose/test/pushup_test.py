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
MODEL_PATH = PROJECT_ROOT / "models" / "pushup_lstm_10f_stride_5.h5"

SEQUENCE_LENGTH = 10
NUM_ANGLES = 8
PRED_BUFFER = 8                    # Increased for better stability
POSE_CONFIRM_FRAMES = 4

# UPDATED THRESHOLD + BIAS (to fix correct pushups being marked wrong)
THRESHOLD = 0.75                   # Higher = more lenient toward "Correct"
BIAS = 0.12                        # Reduces false "Incorrect" predictions

VIDEO_PATH = None
# VIDEO_PATH = PROJECT_ROOT / "pushups_forms" / "correct" / "Copy of push up 164.mp4"

# ===============================
# LOAD MODEL
# ===============================
if not MODEL_PATH.exists():
    raise FileNotFoundError(f"Model file not found: {MODEL_PATH}")

model = load_model(str(MODEL_PATH))
print("Model loaded successfully")

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
# UTILITIES
# ===============================
def normalize_landmarks(frame):
    left_hip = frame[23]
    right_hip = frame[24]
    hip_center = (left_hip + right_hip) / 2
    return frame - hip_center

def calculate_angle(a, b, c):
    ba = a - b
    bc = c - b
    cosine = np.dot(ba, bc) / (np.linalg.norm(ba) * np.linalg.norm(bc) + 1e-6)
    return np.degrees(np.arccos(np.clip(cosine, -1.0, 1.0)))

def extract_angles(frame_landmarks):
    frame = normalize_landmarks(frame_landmarks)
    return np.array([
        calculate_angle(frame[11], frame[13], frame[15]),
        calculate_angle(frame[12], frame[14], frame[16]),
        calculate_angle(frame[13], frame[11], frame[23]),
        calculate_angle(frame[14], frame[12], frame[24]),
        calculate_angle(frame[11], frame[23], frame[25]),
        calculate_angle(frame[12], frame[24], frame[26]),
        calculate_angle(frame[23], frame[25], frame[27]),
        calculate_angle(frame[24], frame[26], frame[28])
    ], dtype=np.float32)

# ===============================
# POSTURE FEEDBACK
# ===============================
def get_posture_feedback(angles, landmarks):
    feedback = []

    avg_elbow = np.mean(angles[0:2])
    avg_shoulder = np.mean(angles[2:4])
    avg_hip = np.mean(angles[4:6])
    avg_knee = np.mean(angles[6:8])

    if avg_hip < 155:
        feedback.append("Raise your hips! Keep body straight.")
    if avg_hip > 190:
        feedback.append("Lower your hips! Avoid piking.")
    if avg_knee < 160:
        feedback.append("Straighten your legs fully.")
    if avg_elbow > 165:
        feedback.append("Lower your body more.")
    if avg_elbow < 70:
        feedback.append("Push up higher.")
    if avg_shoulder < 150:
        feedback.append("Pull shoulders back, elbows closer.")

    avg_shoulder_x = (landmarks[11][0] + landmarks[12][0]) / 2
    avg_wrist_x = (landmarks[15][0] + landmarks[16][0]) / 2
    if avg_wrist_x < avg_shoulder_x - 0.08:
        feedback.append("Place hands under shoulders.")

    if not feedback:
        feedback.append("Good effort! Minor adjustments needed.")

    return " | ".join(feedback[:2])

# ===============================
# PUSH-UP POSTURE CHECK
# ===============================
def is_pushup_pose(landmarks):
    shoulder_y = (landmarks[11][1] + landmarks[12][1]) / 2
    hip_y = (landmarks[23][1] + landmarks[24][1]) / 2
    ankle_y = (landmarks[27][1] + landmarks[28][1]) / 2

    body_slope = abs(shoulder_y - hip_y) + abs(hip_y - ankle_y)
    if body_slope > 0.30:
        return False

    left_elbow = calculate_angle(landmarks[11], landmarks[13], landmarks[15])
    right_elbow = calculate_angle(landmarks[12], landmarks[14], landmarks[16])

    if not (30 < left_elbow < 190 and 30 < right_elbow < 190):
        return False

    return True

# ===============================
# VIDEO SETUP
# ===============================
video_source = str(VIDEO_PATH) if VIDEO_PATH else 0
cap = cv2.VideoCapture(video_source)
cv2.namedWindow("Push-up Form Detection", cv2.WINDOW_NORMAL)
cv2.resizeWindow("Push-up Form Detection", 1280, 720)

sequence_buffer = deque(maxlen=SEQUENCE_LENGTH)
pred_buffer = deque(maxlen=PRED_BUFFER)
pose_valid_counter = 0

print(f"Push-up detection started (Threshold={THRESHOLD}, Bias={BIAS}). Press 'q' to quit.")

# ===============================
# MAIN LOOP
# ===============================
while cap.isOpened():
    ret, frame = cap.read()
    if not ret:
        print("End of video or cannot read frame.")
        break

    frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    results = pose.process(frame_rgb)

    main_text = ""
    feedback_text = ""
    text_color = (255, 255, 255)

    if results.pose_landmarks:
        mp_drawing.draw_landmarks(
            frame, results.pose_landmarks, mp_pose.POSE_CONNECTIONS,
            mp_drawing.DrawingSpec(color=(0, 255, 0), thickness=2, circle_radius=4),
            mp_drawing.DrawingSpec(color=(0, 0, 255), thickness=2)
        )

        landmarks = np.array([[lm.x, lm.y, lm.z] for lm in results.pose_landmarks.landmark])

        if is_pushup_pose(landmarks):
            pose_valid_counter += 1
        else:
            pose_valid_counter = max(0, pose_valid_counter - 1)

        if pose_valid_counter >= POSE_CONFIRM_FRAMES:
            angles = extract_angles(landmarks)
            sequence_buffer.append(angles)

            if len(sequence_buffer) == SEQUENCE_LENGTH:
                input_seq = np.array(sequence_buffer).reshape(1, SEQUENCE_LENGTH, NUM_ANGLES)
                prob_incorrect = model.predict(input_seq, verbose=0)[0][0]
                
                pred_buffer.append(prob_incorrect)
                smooth_prob = np.mean(pred_buffer)

                # Apply bias to reduce false "Incorrect"
                adjusted_prob = max(0.0, smooth_prob - BIAS)

                # === THRESHOLD LOGIC ===
                if adjusted_prob < THRESHOLD:           # More lenient toward Correct
                    label = "Correct"
                    confidence = (1 - adjusted_prob) * 100
                    text_color = (0, 255, 0)
                    feedback_text = "Perfect form! Keep it up!"
                else:
                    label = "Incorrect"
                    confidence = adjusted_prob * 100
                    text_color = (0, 0, 255)
                    feedback_text = get_posture_feedback(angles, landmarks)

                main_text = f"Push-up: {label} ({confidence:.1f}%)"

            else:
                main_text = "Analyzing form..."
                feedback_text = f"Collecting sequence ({len(sequence_buffer)}/{SEQUENCE_LENGTH})"
                text_color = (255, 255, 0)
        else:
            main_text = "Get into push-up position"
            feedback_text = "Align body in straight plank"
            text_color = (0, 255, 255)
    else:
        pose_valid_counter = 0
        sequence_buffer.clear()
        pred_buffer.clear()
        main_text = "No Pose Detected"
        feedback_text = "Make sure full body is in frame"
        text_color = (0, 0, 255)

    # === TEXT DISPLAY ===
    cv2.putText(frame, main_text, (30, 70),
                cv2.FONT_HERSHEY_DUPLEX, 1.4, text_color, 3)

    # Auto-wrap feedback text
    max_width = frame.shape[1] - 60
    font = cv2.FONT_HERSHEY_SIMPLEX
    font_scale = 0.85
    thickness = 2
    line_spacing = 32

    words = feedback_text.split(' ')
    lines = []
    current_line = ""
    for word in words:
        test_line = current_line + (" " + word if current_line else word)
        (w, _), _ = cv2.getTextSize(test_line, font, font_scale, thickness)
        if w <= max_width:
            current_line = test_line
        else:
            if current_line:
                lines.append(current_line)
            current_line = word
            if len(lines) >= 3:
                break
    if current_line:
        lines.append(current_line)

    # Dark semi-transparent background for readability
    overlay = frame.copy()
    cv2.rectangle(overlay, (10, 20), (frame.shape[1]-10, 135 + len(lines)*line_spacing), (0, 0, 0), -1)
    cv2.addWeighted(overlay, 0.45, frame, 0.55, 0, frame)

    # Draw wrapped lines
    for i, line in enumerate(lines[:3]):
        cv2.putText(frame, line, (30, 125 + i * line_spacing),
                    font, font_scale, text_color, thickness)

    cv2.imshow("Push-up Form Detection", frame)

    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()
pose.close()
print("Detection stopped.")