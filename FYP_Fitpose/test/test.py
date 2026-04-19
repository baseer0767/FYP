import cv2
import numpy as np
import mediapipe as mp
from tensorflow.keras.models import load_model
from collections import deque

# ===============================
# PARAMETERS
# ===============================
MODEL_PATH = "pushup_lstm_30f_stride_2.h5"
SEQUENCE_LENGTH = 30  # must match training
NUM_ANGLES = 8
PRED_BUFFER = 5       # smoothing window for stable predictions

# Video input (None for webcam, or path to video file)
VIDEO_PATH = "D:/FIT_pose App/FYP_Fitpose/Deadlift/Incorrect/shayan1.mp4" 
# VIDEO_PATH = None  # Uncomment for live webcam

# ===============================
# LOAD MODEL
# ===============================
model = load_model(MODEL_PATH)
print("✅ Model loaded successfully")

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
    """Normalize landmarks relative to hip center (midpoint between left and right hip)."""
    left_hip = frame[23]
    right_hip = frame[24]
    hip_center = (left_hip + right_hip) / 2
    return frame - hip_center

def calculate_angle(a, b, c):
    """Calculate angle in degrees at joint b."""
    ba = a - b
    bc = c - b
    cosine = np.dot(ba, bc) / (np.linalg.norm(ba) * np.linalg.norm(bc) + 1e-6)
    return np.degrees(np.arccos(np.clip(cosine, -1.0, 1.0)))

def extract_angles(frame_landmarks):
    """Extract 8 key joint angles from normalized landmarks."""
    frame = normalize_landmarks(frame_landmarks)
    angles = [
        calculate_angle(frame[11], frame[13], frame[15]),  # Left elbow
        calculate_angle(frame[12], frame[14], frame[16]),  # Right elbow
        calculate_angle(frame[13], frame[11], frame[23]),  # Left shoulder
        calculate_angle(frame[14], frame[12], frame[24]),  # Right shoulder
        calculate_angle(frame[11], frame[23], frame[25]),  # Left hip
        calculate_angle(frame[12], frame[24], frame[26]),  # Right hip
        calculate_angle(frame[23], frame[25], frame[27]),  # Left knee
        calculate_angle(frame[24], frame[26], frame[28])   # Right knee
    ]
    return np.array(angles)

# ===============================
# VIDEO CAPTURE SETUP
# ===============================
cap = cv2.VideoCapture(VIDEO_PATH if VIDEO_PATH else 0)

cv2.namedWindow("Push-up Form Detection", cv2.WINDOW_NORMAL)
cv2.resizeWindow("Push-up Form Detection", 1280, 720)  # Adjust size if needed

sequence_buffer = deque(maxlen=SEQUENCE_LENGTH)
pred_buffer = deque(maxlen=PRED_BUFFER)

print("🚀 Starting real-time push-up form detection. Press 'q' to quit.")

while cap.isOpened():
    ret, frame = cap.read()
    if not ret:
        print("End of video or cannot read frame.")
        break

    frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    results = pose.process(frame_rgb)

    if results.pose_landmarks:
        # Draw pose landmarks and connections
        mp_drawing.draw_landmarks(
            frame,
            results.pose_landmarks,
            mp_pose.POSE_CONNECTIONS,
            mp_drawing.DrawingSpec(color=(0, 255, 0), thickness=2, circle_radius=2),
            mp_drawing.DrawingSpec(color=(0, 0, 255), thickness=2)
        )

        # Extract 33 landmarks × 3 (x, y, z)
        landmarks = np.array([[lm.x, lm.y, lm.z] for lm in results.pose_landmarks.landmark])
        angles = extract_angles(landmarks)
        sequence_buffer.append(angles)

        # Only predict when we have a full sequence
        if len(sequence_buffer) == SEQUENCE_LENGTH:
            input_seq = np.array(sequence_buffer).reshape(1, SEQUENCE_LENGTH, NUM_ANGLES)
            pred_prob = model.predict(input_seq, verbose=0)[0][0]

            # Smooth prediction over last few frames
            pred_buffer.append(pred_prob)
            smoothed_pred = np.mean(pred_buffer)

            # FIXED LABEL LOGIC
            label = "Incorrect" if smoothed_pred > 0.5 else "Correct"
            confidence = smoothed_pred if label == "Incorrect" else (1 - smoothed_pred)
            color = (0, 255, 0) if label == "Correct" else (0, 0, 255)

            # Display result
            cv2.putText(frame, f"Push-up: {label} ({confidence:.2f})", (30, 50),
                        cv2.FONT_HERSHEY_SIMPLEX, 1.2, color, 3)

    else:
        # No pose detected
        cv2.putText(frame, "No Pose Detected", (30, 50),
                    cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 0, 255), 3)

    # Show frame
    cv2.imshow("Push-up Form Detection", frame)

    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

# Cleanup
cap.release()
cv2.destroyAllWindows()
pose.close()
print("👋 Detection stopped.")