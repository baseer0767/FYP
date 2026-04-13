import cv2
import mediapipe as mp
import numpy as np
import csv
import os

# ===============================
# PARAMETERS
# ===============================
VIDEO_DIR = "D:/FIT_pose App/FYP_Fitpose/Deadlift/Incorrect"   # change folder for each class
LABEL = "incorrect"                      # correct / incorrect
SEQUENCE_LENGTH = 30
STRIDE = SEQUENCE_LENGTH // 2             # 50% overlap
CSV_OUTPUT = "deadlift_sequences_raw.csv"

# ===============================
# MEDIAPIPE INIT
# ===============================
mp_pose = mp.solutions.pose
pose = mp_pose.Pose(
    static_image_mode=False,
    model_complexity=1,
    min_detection_confidence=0.5,
    min_tracking_confidence=0.5
)

# ===============================
# FEATURE EXTRACTION
# ===============================
def extract_raw_landmarks(frame):
    frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    results = pose.process(frame_rgb)

    if not results.pose_landmarks:
        return [0.0] * 99

    features = []
    for lm in results.pose_landmarks.landmark:
        features.extend([lm.x, lm.y, lm.z])   # ❌ visibility removed
    return features

# ===============================
# PROCESS ALL VIDEOS
# ===============================
rows = []

video_files = [
    f for f in os.listdir(VIDEO_DIR)
    if f.lower().endswith((".mp4", ".avi", ".mov"))
]

print(f"📂 Found {len(video_files)} videos")

for video_name in video_files:
    video_path = os.path.join(VIDEO_DIR, video_name)
    print(f"🎥 Processing: {video_name}")

    cap = cv2.VideoCapture(video_path)
    frame_buffer = []

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break

        features = extract_raw_landmarks(frame)
        frame_buffer.append(features)

        # Sliding window sequence
        if len(frame_buffer) == SEQUENCE_LENGTH:
            row = np.array(frame_buffer).flatten().tolist()
            row.append(LABEL)
            rows.append(row)

            # keep 50% frames for next sequence
            frame_buffer = frame_buffer[STRIDE:]

    cap.release()

pose.close()

# ===============================
# CSV SAVE (HEADER ONCE)
# ===============================
file_exists = os.path.isfile(CSV_OUTPUT)
file_empty = not file_exists or os.path.getsize(CSV_OUTPUT) == 0

with open(CSV_OUTPUT, "a", newline="") as f:
    writer = csv.writer(f)

    if file_empty:
        header = []
        for i in range(SEQUENCE_LENGTH):
            for j in range(99):
                header.append(f"f{i}_{j}")
        header.append("label")
        writer.writerow(header)

    writer.writerows(rows)

print(f"✅ Appended {len(rows)} sequences to {CSV_OUTPUT}")
