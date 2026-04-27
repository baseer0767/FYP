import numpy as np
import pandas as pd
import tensorflow as tf
from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import LSTM, Dense, Dropout, BatchNormalization
from tensorflow.keras.callbacks import EarlyStopping, ReduceLROnPlateau
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import confusion_matrix, ConfusionMatrixDisplay, roc_curve, auc, classification_report
import matplotlib.pyplot as plt
from pathlib import Path

# ===============================
# PARAMETERS
# ===============================
PROJECT_ROOT = Path(__file__).resolve().parent.parent
CSV_PATH = PROJECT_ROOT / "features" / "deadlift_sequences_raw.csv"

SEQUENCE_LENGTH = 10
STRIDE = 5

NUM_LANDMARKS = 33
XYZ = 3
NUM_ANGLES = 9   # 8 angles + hip height

# ===============================
# LOAD DATA
# ===============================
df = pd.read_csv(CSV_PATH)

X_raw = df.iloc[:, :-1].values
y_raw = df.iloc[:, -1].values

features_per_frame = NUM_LANDMARKS * XYZ

# ===============================
# SAFE VALIDATION (IMPORTANT FIX)
# ===============================
if X_raw.shape[1] % features_per_frame != 0:
    raise ValueError(
        f"Invalid feature width {X_raw.shape[1]} (must be multiple of {features_per_frame})"
    )

original_sequence_length = X_raw.shape[1] // features_per_frame

# reshape safely
X_raw = X_raw.reshape(-1, original_sequence_length, NUM_LANDMARKS, XYZ)

# FIX: ensure labels match samples
if len(X_raw) != len(y_raw):
    raise ValueError(
        f"Mismatch after reshape: X={len(X_raw)} vs y={len(y_raw)}"
    )

print(f"Loaded {len(X_raw)} samples | Each sequence length: {original_sequence_length}")

# ===============================
# PREPROCESSING
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


def extract_angles(sequence):
    angles_seq = []

    for frame in sequence:
        frame = normalize_landmarks(frame)

        angles = [
            calculate_angle(frame[11], frame[23], frame[25]),
            calculate_angle(frame[12], frame[24], frame[26]),
            calculate_angle(frame[23], frame[25], frame[27]),
            calculate_angle(frame[24], frame[26], frame[28]),
            calculate_angle(frame[7], frame[11], frame[23]),
            calculate_angle(frame[8], frame[12], frame[24]),
            calculate_angle(frame[13], frame[11], frame[23]),
            calculate_angle(frame[14], frame[12], frame[24]),
        ]

        hip_height = (frame[23][1] + frame[24][1]) / 2
        angles.append(hip_height)

        angles_seq.append(angles)

    return np.array(angles_seq)

# ===============================
# CREATE SEQUENCES (SAFE VERSION)
# ===============================
def create_sequences_with_stride(X_data, y_data, seq_len, stride):
    sequences = []
    labels = []

    for i in range(len(X_data)):
        video_seq = X_data[i]
        label = y_data[i]

        total_frames = video_seq.shape[0]

        # FIX: safe boundary
        if total_frames < seq_len:
            continue

        for start in range(0, total_frames - seq_len + 1, stride):
            end = start + seq_len

            seq = video_seq[start:end]
            if seq.shape[0] != seq_len:
                continue

            seq_angles = extract_angles(seq)

            # FIX: safety check
            if seq_angles.shape[0] == seq_len:
                sequences.append(seq_angles)
                labels.append(label)

    return np.array(sequences), np.array(labels)


X_sequences, y_sequences = create_sequences_with_stride(
    X_raw, y_raw, SEQUENCE_LENGTH, STRIDE
)

print(f"Created {len(X_sequences)} training sequences")

# ===============================
# LABEL ENCODING
# ===============================
le = LabelEncoder()
y_encoded = le.fit_transform(y_sequences)

# ===============================
# TRAIN TEST SPLIT
# ===============================
X_train, X_test, y_train, y_test = train_test_split(
    X_sequences,
    y_encoded,
    test_size=0.2,
    random_state=42,
    shuffle=True
)

# ===============================
# MODEL
# ===============================
model = Sequential([
    LSTM(128, return_sequences=True, input_shape=(SEQUENCE_LENGTH, NUM_ANGLES)),
    BatchNormalization(),
    Dropout(0.4),

    LSTM(64),
    BatchNormalization(),
    Dropout(0.4),

    Dense(64, activation="relu"),
    Dense(1, activation="sigmoid")
])

model.compile(
    optimizer=tf.keras.optimizers.Adam(learning_rate=0.001),
    loss="binary_crossentropy",
    metrics=["accuracy"]
)

# ===============================
# CALLBACKS
# ===============================
callbacks = [
    EarlyStopping(patience=12, restore_best_weights=True),
    ReduceLROnPlateau(patience=6, factor=0.5)
]

# ===============================
# TRAIN
# ===============================
history = model.fit(
    X_train, y_train,
    validation_split=0.2,
    epochs=300,
    batch_size=32,
    callbacks=callbacks,
    verbose=1
)

# ===============================
# EVALUATION
# ===============================
train_loss, train_acc = model.evaluate(X_train, y_train, verbose=0)
print(f"Train Accuracy: {train_acc * 100:.2f}%")

test_loss, test_acc = model.evaluate(X_test, y_test, verbose=0)
print(f"Test Accuracy: {test_acc * 100:.2f}%")

# ===============================
# SAVE MODEL
# ===============================
model.save("deadlift_lstm_model.h5")
print("Model saved successfully")

# ===============================
# PREDICTIONS
# ===============================
y_pred_prob = model.predict(X_test, verbose=0)
y_pred = (y_pred_prob > 0.5).astype(int).flatten()

# Confusion Matrix
cm = confusion_matrix(y_test, y_pred)
ConfusionMatrixDisplay(cm, display_labels=le.classes_).plot()
plt.title("Confusion Matrix")
plt.show()

# Classification Report
print(classification_report(y_test, y_pred, target_names=le.classes_))

# ROC
fpr, tpr, _ = roc_curve(y_test, y_pred_prob)
roc_auc = auc(fpr, tpr)

plt.plot(fpr, tpr, label=f"AUC={roc_auc:.2f}")
plt.plot([0,1],[0,1],"--")
plt.legend()
plt.title("ROC Curve")
plt.show()

# Training curves
plt.figure(figsize=(12,5))

plt.subplot(1,2,1)
plt.plot(history.history["accuracy"])
plt.plot(history.history["val_accuracy"])
plt.title("Accuracy")

plt.subplot(1,2,2)
plt.plot(history.history["loss"])
plt.plot(history.history["val_loss"])
plt.title("Loss")

plt.show()