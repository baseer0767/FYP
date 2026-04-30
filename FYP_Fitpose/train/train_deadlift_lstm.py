import numpy as np
import pandas as pd
import tensorflow as tf
from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import LSTM, Dense, Dropout, BatchNormalization
from tensorflow.keras.callbacks import EarlyStopping, ReduceLROnPlateau
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.metrics import confusion_matrix, ConfusionMatrixDisplay, roc_curve, auc, classification_report
import matplotlib.pyplot as plt
from pathlib import Path
import joblib

# ===============================
# PARAMETERS
# ===============================
PROJECT_ROOT = Path(__file__).resolve().parent.parent
CSV_PATH = PROJECT_ROOT / "features" / "deadlift_sequences_raw.csv"

SEQUENCE_LENGTH = 20
STRIDE = 10

NUM_LANDMARKS = 33
XYZ = 3
NUM_FEATURES = 15

# ===============================
# LOAD DATA
# ===============================
df = pd.read_csv(CSV_PATH)

X_raw = df.iloc[:, :-1].values
y_raw = df.iloc[:, -1].values

features_per_frame = NUM_LANDMARKS * XYZ

if X_raw.shape[1] % features_per_frame != 0:
    raise ValueError("Invalid feature width")

original_sequence_length = X_raw.shape[1] // features_per_frame
X_raw = X_raw.reshape(-1, original_sequence_length, NUM_LANDMARKS, XYZ)

print(f"Loaded {len(X_raw)} samples")

# ===============================
# HELPER FUNCTIONS
# ===============================
def normalize_landmarks(frame):
    hip_center = (frame[23] + frame[24]) / 2
    return frame - hip_center


def calculate_angle(a, b, c):
    ba = a - b
    bc = c - b
    cosine = np.dot(ba, bc) / (np.linalg.norm(ba) * np.linalg.norm(bc) + 1e-6)
    return np.degrees(np.arccos(np.clip(cosine, -1.0, 1.0)))


def extract_features(sequence):
    features_seq = []
    prev_hip_y, prev_shoulder_y = None, None

    for frame in sequence:
        frame = normalize_landmarks(frame)

        # Angles
        left_hip = calculate_angle(frame[11], frame[23], frame[25])
        right_hip = calculate_angle(frame[12], frame[24], frame[26])
        left_knee = calculate_angle(frame[23], frame[25], frame[27])
        right_knee = calculate_angle(frame[24], frame[26], frame[28])
        left_torso = calculate_angle(frame[7], frame[11], frame[23])
        right_torso = calculate_angle(frame[8], frame[12], frame[24])
        left_sh = calculate_angle(frame[13], frame[11], frame[23])
        right_sh = calculate_angle(frame[14], frame[12], frame[24])

        # Heights
        hip_y = (frame[23][1] + frame[24][1]) / 2
        shoulder_y = (frame[11][1] + frame[12][1]) / 2

        # Velocity
        if prev_hip_y is None:
            hip_v, shoulder_v = 0, 0
        else:
            hip_v = hip_y - prev_hip_y
            shoulder_v = shoulder_y - prev_shoulder_y

        prev_hip_y, prev_shoulder_y = hip_y, shoulder_y

        # Symmetry
        hip_sym = abs(left_hip - right_hip)
        knee_sym = abs(left_knee - right_knee)

        # Bar path
        hand_x = (frame[15][0] + frame[16][0]) / 2
        hip_x = (frame[23][0] + frame[24][0]) / 2
        bar_offset = abs(hand_x - hip_x)

        # Spine proxy
        spine_angle = calculate_angle(
            (frame[11] + frame[12]) / 2,
            (frame[23] + frame[24]) / 2,
            (frame[25] + frame[26]) / 2
        )

        features = [
            left_hip, right_hip,
            left_knee, right_knee,
            left_torso, right_torso,
            left_sh, right_sh,
            hip_y,
            hip_v, shoulder_v,
            hip_sym, knee_sym,
            bar_offset,
            spine_angle
        ]

        features_seq.append(features)

    return np.array(features_seq)

# ===============================
# CREATE SEQUENCES
# ===============================
def create_sequences(X_data, y_data):
    sequences, labels = [], []

    for i in range(len(X_data)):
        video = X_data[i]
        label = y_data[i]

        for start in range(0, len(video) - SEQUENCE_LENGTH + 1, STRIDE):
            seq = video[start:start + SEQUENCE_LENGTH]
            features = extract_features(seq)

            if features.shape[0] == SEQUENCE_LENGTH:
                sequences.append(features)
                labels.append(label)

    return np.array(sequences), np.array(labels)


X_sequences, y_sequences = create_sequences(X_raw, y_raw)
print(f"Sequences: {len(X_sequences)}")

# ===============================
# SCALING
# ===============================
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X_sequences.reshape(-1, NUM_FEATURES))
X_sequences = X_scaled.reshape(-1, SEQUENCE_LENGTH, NUM_FEATURES)

joblib.dump(scaler, "deadlift_scaler.save")

# ===============================
# LABEL ENCODING
# ===============================
le = LabelEncoder()
y_encoded = le.fit_transform(y_sequences)

# ===============================
# SPLIT
# ===============================
X_train, X_test, y_train, y_test = train_test_split(
    X_sequences, y_encoded, test_size=0.2, random_state=42
)

# ===============================
# MODEL
# ===============================
model = Sequential([
    LSTM(128, return_sequences=True, input_shape=(SEQUENCE_LENGTH, NUM_FEATURES)),
    BatchNormalization(),
    Dropout(0.4),

    LSTM(64),
    BatchNormalization(),
    Dropout(0.4),

    Dense(64, activation="relu"),
    Dense(1, activation="sigmoid")
])

model.compile(optimizer="adam", loss="binary_crossentropy", metrics=["accuracy"])

# ===============================
# TRAIN
# ===============================
callbacks = [
    EarlyStopping(patience=12, restore_best_weights=True),
    ReduceLROnPlateau(patience=6)
]

history = model.fit(
    X_train, y_train,
    validation_split=0.2,
    epochs=200,
    batch_size=32,
    callbacks=callbacks
)

# ===============================
# EVALUATION
# ===============================
print("Train:", model.evaluate(X_train, y_train, verbose=0))
print("Test:", model.evaluate(X_test, y_test, verbose=0))

# ===============================
# SAVE MODEL
# ===============================
model.save("deadlift_lstm_model_20f_v2.h5")

# ===============================
# PREDICTIONS
# ===============================
y_pred_prob = model.predict(X_test)
y_pred = (y_pred_prob > 0.5).astype(int)

# ===============================
# CONFUSION MATRIX
# ===============================
cm = confusion_matrix(y_test, y_pred)
ConfusionMatrixDisplay(cm, display_labels=le.classes_).plot()
plt.title("Confusion Matrix")
plt.show()

# ===============================
# CLASSIFICATION REPORT
# ===============================
print(classification_report(y_test, y_pred, target_names=le.classes_))

# ===============================
# ROC CURVE
# ===============================
fpr, tpr, _ = roc_curve(y_test, y_pred_prob)
roc_auc = auc(fpr, tpr)

plt.plot(fpr, tpr, label=f"AUC = {roc_auc:.2f}")
plt.plot([0, 1], [0, 1], "--")
plt.title("ROC Curve")
plt.legend()
plt.show()

# ===============================
# TRAINING CURVES
# ===============================
plt.figure(figsize=(12, 5))

plt.subplot(1, 2, 1)
plt.plot(history.history["accuracy"])
plt.plot(history.history["val_accuracy"])
plt.title("Accuracy")

plt.subplot(1, 2, 2)
plt.plot(history.history["loss"])
plt.plot(history.history["val_loss"])
plt.title("Loss")

plt.show()