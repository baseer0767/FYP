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

# ===============================
# PARAMETERS
# ===============================
CSV_PATH = "pose_sequences_raw.csv"
SEQUENCE_LENGTH = 30
STRIDE = 15                 # Overlap 50%
NUM_LANDMARKS = 33
XYZ = 3
NUM_ANGLES = 8

# ===============================
# LOAD DATA
# ===============================
df = pd.read_csv(CSV_PATH)
X_raw = df.iloc[:, :-1].values
y_raw = df.iloc[:, -1].values

# ===============================
# RESHAPE RAW DATA PER VIDEO
# ===============================
# Assuming CSV rows are already in sequences; if not, you need to group per video
X_raw = X_raw.reshape(-1, SEQUENCE_LENGTH, NUM_LANDMARKS, XYZ)

# ===============================
# PREPROCESSING FUNCTIONS
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
            calculate_angle(frame[11], frame[13], frame[15]),  # L elbow
            calculate_angle(frame[12], frame[14], frame[16]),  # R elbow
            calculate_angle(frame[13], frame[11], frame[23]),  # L shoulder
            calculate_angle(frame[14], frame[12], frame[24]),  # R shoulder
            calculate_angle(frame[11], frame[23], frame[25]),  # L hip
            calculate_angle(frame[12], frame[24], frame[26]),  # R hip
            calculate_angle(frame[23], frame[25], frame[27]),  # L knee
            calculate_angle(frame[24], frame[26], frame[28])   # R knee
        ]
        angles_seq.append(angles)
    return np.array(angles_seq)

# ===============================
# CREATE OVERLAPPING SEQUENCES WITH STRIDE
# ===============================
def create_sequences_with_stride(X_data, y_data, seq_len=30, stride=15):
    sequences = []
    labels = []
    for i in range(len(X_data)):
        video_seq = X_data[i]  # shape: SEQUENCE_LENGTH x 33 x 3
        label = y_data[i]
        total_frames = video_seq.shape[0]
        for start in range(0, total_frames - seq_len + 1, stride):
            end = start + seq_len
            seq = video_seq[start:end]
            seq_angles = extract_angles(seq)
            sequences.append(seq_angles)
            labels.append(label)
    return np.array(sequences), np.array(labels)

X_sequences, y_sequences = create_sequences_with_stride(X_raw, y_raw, SEQUENCE_LENGTH, STRIDE)

# ===============================
# ENCODE LABELS
# ===============================
le = LabelEncoder()
y_encoded = le.fit_transform(y_sequences)

# ===============================
# TRAIN / TEST SPLIT
# ===============================
X_train, X_test, y_train, y_test = train_test_split(
    X_sequences, y_encoded, test_size=0.2, random_state=None, shuffle=True
)

# ===============================
# MODEL ARCHITECTURE
# ===============================
model = Sequential([
    LSTM(128, return_sequences=True, input_shape=(SEQUENCE_LENGTH, NUM_ANGLES)),
    BatchNormalization(),
    Dropout(0.3),

    LSTM(64),
    BatchNormalization(),
    Dropout(0.3),

    Dense(32, activation="relu"),
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
    epochs=500,
    batch_size=16,
    callbacks=callbacks
)

# ===============================
# EVALUATE TRAINING AND TEST ACCURACY
# ===============================
train_loss, train_acc = model.evaluate(X_train, y_train, verbose=0)
print(f"✅ Training Accuracy: {train_acc * 100:.2f}%")

test_loss, test_acc = model.evaluate(X_test, y_test, verbose=0)
print(f"✅ Test Accuracy: {test_acc * 100:.2f}%")

# ===============================
# SAVE MODEL
# ===============================
model.save("pushup_lstm_30f_stride_2.h5")
print("💾 Model saved as pushup_lstm_30f_stride_2.h5")

# ===============================
# PREDICTIONS ON TEST SET
# ===============================
y_pred_prob = model.predict(X_test, verbose=0)
y_pred = (y_pred_prob > 0.5).astype(int).flatten()

# ===============================
# CONFUSION MATRIX
# ===============================
cm = confusion_matrix(y_test, y_pred)
disp = ConfusionMatrixDisplay(confusion_matrix=cm, display_labels=le.classes_)
disp.plot(cmap=plt.cm.Blues)
plt.title("Confusion Matrix")
plt.show()

# ===============================
# CLASSIFICATION REPORT
# ===============================
print("Classification Report:\n")
print(classification_report(y_test, y_pred, target_names=le.classes_))

# ===============================
# ROC CURVE
# ===============================
fpr, tpr, thresholds = roc_curve(y_test, y_pred_prob)
roc_auc = auc(fpr, tpr)

plt.figure()
plt.plot(fpr, tpr, color='blue', lw=2, label=f'ROC curve (AUC = {roc_auc:.2f})')
plt.plot([0, 1], [0, 1], color='gray', lw=1, linestyle='--')
plt.xlim([0.0, 1.0])
plt.ylim([0.0, 1.05])
plt.xlabel('False Positive Rate')
plt.ylabel('True Positive Rate')
plt.title('Receiver Operating Characteristic (ROC) Curve')
plt.legend(loc="lower right")
plt.show()

# ===============================
# TRAINING AND VALIDATION CURVES
# ===============================
plt.figure(figsize=(12,5))

# Accuracy
plt.subplot(1,2,1)
plt.plot(history.history['accuracy'], label='Train Accuracy')
plt.plot(history.history['val_accuracy'], label='Validation Accuracy')
plt.xlabel('Epoch')
plt.ylabel('Accuracy')
plt.title('Training and Validation Accuracy')
plt.legend()

# Loss
plt.subplot(1,2,2)
plt.plot(history.history['loss'], label='Train Loss')
plt.plot(history.history['val_loss'], label='Validation Loss')
plt.xlabel('Epoch')
plt.ylabel('Loss')
plt.title('Training and Validation Loss')
plt.legend()

plt.show()
