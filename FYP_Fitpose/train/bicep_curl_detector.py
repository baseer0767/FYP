import pickle
import cv2
import numpy as np
import mediapipe as mp

mp_pose = mp.solutions.pose


def calculate_angle(a, b, c):
    """Return the angle (in degrees) at point b defined by three 2‑D points.

    Accepts lists or arrays for points; coerces to numpy arrays.
    """
    a = np.array(a, dtype=np.float32)
    b = np.array(b, dtype=np.float32)
    c = np.array(c, dtype=np.float32)
    ba = a - b
    bc = c - b
    cosine = np.dot(ba, bc) / (np.linalg.norm(ba) * np.linalg.norm(bc) + 1e-6)
    return float(np.degrees(np.arccos(np.clip(cosine, -1.0, 1.0))))


def extract_important_keypoints(mp_results, important_landmarks):
    """Pull out a flat list of (x,y,z,visibility) values for the landmarks we care about."""
    row = []
    for lm_name in important_landmarks:
        lm = mp_results.pose_landmarks.landmark[getattr(mp_pose.PoseLandmark, lm_name).value]
        row.extend([lm.x, lm.y, lm.z, lm.visibility])
    return row


class BicepPoseAnalysis:
    def __init__(
        self,
        side: str,
        stage_down_threshold: float,
        stage_up_threshold: float,
        peak_contraction_threshold: float,
        loose_upper_arm_angle_threshold: float,
        visibility_threshold: float,
    ):
        self.stage_down_threshold = stage_down_threshold
        self.stage_up_threshold = stage_up_threshold
        self.peak_contraction_threshold = peak_contraction_threshold
        self.loose_upper_arm_angle_threshold = loose_upper_arm_angle_threshold
        self.visibility_threshold = visibility_threshold

        self.side = side
        self.counter = 0
        self.stage = "down"
        self.is_visible = True
        self.detected_errors = {"LOOSE_UPPER_ARM": 0, "PEAK_CONTRACTION": 0}
        self.loose_upper_arm = False
        self.peak_contraction_angle = 1000

    def get_joints(self, landmarks) -> bool:
        side = self.side.upper()
        joints_visibility = [
            landmarks[mp_pose.PoseLandmark[f"{side}_SHOULDER"].value].visibility,
            landmarks[mp_pose.PoseLandmark[f"{side}_ELBOW"].value].visibility,
            landmarks[mp_pose.PoseLandmark[f"{side}_WRIST"].value].visibility,
        ]
        is_visible = all(vis > self.visibility_threshold for vis in joints_visibility)
        self.is_visible = is_visible
        if not is_visible:
            return self.is_visible

        self.shoulder = [
            landmarks[mp_pose.PoseLandmark[f"{side}_SHOULDER"].value].x,
            landmarks[mp_pose.PoseLandmark[f"{side}_SHOULDER"].value].y,
        ]
        self.elbow = [
            landmarks[mp_pose.PoseLandmark[f"{side}_ELBOW"].value].x,
            landmarks[mp_pose.PoseLandmark[f"{side}_ELBOW"].value].y,
        ]
        self.wrist = [
            landmarks[mp_pose.PoseLandmark[f"{side}_WRIST"].value].x,
            landmarks[mp_pose.PoseLandmark[f"{side}_WRIST"].value].y,
        ]
        return self.is_visible

    def analyze_pose(
        self,
        landmarks,
        frame,
        results,
        timestamp: int,
        lean_back_error: bool = False,
    ):
        has_error = False
        self.get_joints(landmarks)
        if not self.is_visible:
            return (None, None, has_error)

        bicep_curl_angle = int(calculate_angle(self.shoulder, self.elbow, self.wrist))
        if bicep_curl_angle > self.stage_down_threshold:
            self.stage = "down"
        elif bicep_curl_angle < self.stage_up_threshold and self.stage == "down":
            self.stage = "up"
            self.counter += 1

        shoulder_projection = [self.shoulder[0], 1]
        ground_upper_arm_angle = int(
            calculate_angle(self.elbow, self.shoulder, shoulder_projection)
        )

        if lean_back_error:
            return (bicep_curl_angle, ground_upper_arm_angle, has_error)

        if ground_upper_arm_angle > self.loose_upper_arm_angle_threshold:
            has_error = True
            self.detected_errors["LOOSE_UPPER_ARM"] += 1
            results.append({"stage": "loose upper arm", "frame": frame, "timestamp": timestamp})
        else:
            self.loose_upper_arm = False

        if self.stage == "up" and bicep_curl_angle < self.peak_contraction_angle:
            self.peak_contraction_angle = bicep_curl_angle

        elif self.stage == "down":
            if (
                self.peak_contraction_angle != 1000
                and self.peak_contraction_angle >= self.peak_contraction_threshold
            ):
                has_error = True
                self.detected_errors["PEAK_CONTRACTION"] += 1
                results.append({"stage": "peak contraction", "frame": frame, "timestamp": timestamp})
            self.peak_contraction_angle = 1000

        return (bicep_curl_angle, ground_upper_arm_angle, has_error)

    def get_counter(self) -> int:
        return self.counter

    def reset(self):
        self.counter = 0
        self.stage = "down"
        self.is_visible = True
        self.detected_errors = {"LOOSE_UPPER_ARM": 0, "PEAK_CONTRACTION": 0}
        self.loose_upper_arm = False
        self.peak_contraction_angle = 1000


class BicepCurlDetector:
    """Simplified port of Exercise‑Correction's bicep curl detector.

    Loads a scikit‑learn model + scaler (KNN by default) and provides a
    :meth:`detect` method that mirrors the original behaviour.
    """

    def __init__(self, model_path: str, scaler_path: str):
        # thresholds copied from original repo
        self.VISIBILITY_THRESHOLD = 0.65
        self.STAGE_UP_THRESHOLD = 100
        self.STAGE_DOWN_THRESHOLD = 120
        self.PEAK_CONTRACTION_THRESHOLD = 60
        self.LOOSE_UPPER_ARM_ANGLE_THRESHOLD = 40
        self.POSTURE_ERROR_THRESHOLD = 0.95

        self.model_path = model_path
        self.scaler_path = scaler_path
        self._load_model()

        self.left_arm_analysis = BicepPoseAnalysis(
            side="left",
            stage_down_threshold=self.STAGE_DOWN_THRESHOLD,
            stage_up_threshold=self.STAGE_UP_THRESHOLD,
            peak_contraction_threshold=self.PEAK_CONTRACTION_THRESHOLD,
            loose_upper_arm_angle_threshold=self.LOOSE_UPPER_ARM_ANGLE_THRESHOLD,
            visibility_threshold=self.VISIBILITY_THRESHOLD,
        )

        self.right_arm_analysis = BicepPoseAnalysis(
            side="right",
            stage_down_threshold=self.STAGE_DOWN_THRESHOLD,
            stage_up_threshold=self.STAGE_UP_THRESHOLD,
            peak_contraction_threshold=self.PEAK_CONTRACTION_THRESHOLD,
            loose_upper_arm_angle_threshold=self.LOOSE_UPPER_ARM_ANGLE_THRESHOLD,
            visibility_threshold=self.VISIBILITY_THRESHOLD,
        )

        self.important_landmarks = [
            "NOSE",
            "LEFT_SHOULDER",
            "RIGHT_SHOULDER",
            "RIGHT_ELBOW",
            "LEFT_ELBOW",
            "RIGHT_WRIST",
            "LEFT_WRIST",
            "LEFT_HIP",
            "RIGHT_HIP",
        ]

        self.headers = ["label"]
        for lm in self.important_landmarks:
            self.headers += [f"{lm.lower()}_x", f"{lm.lower()}_y", f"{lm.lower()}_z", f"{lm.lower()}_v"]

        self.stand_posture = 0
        self.previous_stand_posture = 0
        self.results = []
        self.has_error = False

    def _load_model(self):
        with open(self.model_path, "rb") as f:
            self.model = pickle.load(f)
        with open(self.scaler_path, "rb") as f2:
            self.input_scaler = pickle.load(f2)

    def reset(self):
        self.stand_posture = 0
        self.previous_stand_posture = 0
        self.results = []
        self.has_error = False
        self.left_arm_analysis.reset()
        self.right_arm_analysis.reset()

    def detect(self, mp_results, image, timestamp: int):
        """Run detection on a single MediaPipe result frame.

        Returns a tuple ``(results_list, counters_dict, has_error)`` where
        ``results_list`` contains any error stages found with saved frames,
        ``counters_dict`` reports left/right rep counters and ``has_error``
        indicates whether any error occurred in the frame.
        """
        self.has_error = False
        video_dimensions = [image.shape[1], image.shape[0]]
        landmarks = mp_results.pose_landmarks.landmark

        # posture model
        row = extract_important_keypoints(mp_results, self.important_landmarks)
        X = np.array(row).reshape(1, -1)
        X = self.input_scaler.transform(X)
        predicted_class = self.model.predict(X)[0]
        prediction_probabilities = self.model.predict_proba(X)[0]
        class_prediction_probability = round(prediction_probabilities[np.argmax(prediction_probabilities)], 2)
        if class_prediction_probability >= self.POSTURE_ERROR_THRESHOLD:
            self.stand_posture = predicted_class

        if self.stand_posture == "L":
            if self.previous_stand_posture != self.stand_posture:
                self.results.append({"stage": "lean too far back", "frame": image, "timestamp": timestamp})
            self.has_error = True
        self.previous_stand_posture = self.stand_posture

        # arm analyses
        left_bicep_angle, left_ground_angle, left_err = self.left_arm_analysis.analyze_pose(
            landmarks=landmarks,
            frame=image,
            results=self.results,
            timestamp=timestamp,
            lean_back_error=(self.stand_posture == "L"),
        )
        right_bicep_angle, right_ground_angle, right_err = self.right_arm_analysis.analyze_pose(
            landmarks=landmarks,
            frame=image,
            results=self.results,
            timestamp=timestamp,
            lean_back_error=(self.stand_posture == "L"),
        )

        self.has_error = bool(self.has_error or left_err or right_err)

        return self.results, {"left_counter": self.left_arm_analysis.get_counter(), "right_counter": self.right_arm_analysis.get_counter()}, self.has_error
