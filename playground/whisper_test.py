""" whisper by openAI

play code for fun!
"""

import whisper
import os 
# import sys
# import tqdm

# CustomProgressBar
# class _CustomProgressBar(tqdm.tqdm):
#     """cited from:
#     https://github.com/openai/whisper/discussions/850#discussioncomment-5443424
#     """
#     def __init__(self, *args, **kwargs):
#         super().__init__(*args, **kwargs)
#         self._current = self.n  # Set the initial value
        
#     def update(self, n):
#         super().update(n)
#         self._current += n
        
#         # Handle progress here
#         print("Progress: " + str(self._current) + "/" + str(self.total))

# # Inject into tqdm.tqdm of Whisper, so we can see progress
# import whisper.transcribe 
# transcribe_module = sys.modules['whisper.transcribe']
# transcribe_module.tqdm.tqdm = _CustomProgressBar

from datetime import datetime

audio_name="Anth160b_l11.m4a"

time_stamp = hex(int(datetime.now().timestamp()))

dir_path = os.path.join(os.path.dirname(os.path.realpath(__file__)), "data")

if not os.path.exists(dir_path):
    os.makedirs(dir_path)

audio_path=os.path.join(dir_path, audio_name)

# choices are
# |  Size  | Parameters | English-only model | Multilingual model | Required VRAM | Relative speed |
# |:------:|:----------:|:------------------:|:------------------:|:-------------:|:--------------:|
# |  tiny  |    39 M    |     `tiny.en`      |       `tiny`       |     ~1 GB     |      ~32x      |
# |  base  |    74 M    |     `base.en`      |       `base`       |     ~1 GB     |      ~16x      |
# | small  |   244 M    |     `small.en`     |      `small`       |     ~2 GB     |      ~6x       |
# | medium |   769 M    |    `medium.en`     |      `medium`      |     ~5 GB     |      ~2x       |
# | large  |   1550 M   |        N/A         |      `large`       |    ~10 GB     |       1x       |
model = whisper.load_model("medium")

# load audio and pad/trim it to fit 30 seconds
audio = whisper.load_audio(audio_path)
head_audio = whisper.pad_or_trim(audio)

# make log-Mel spectrogram and move to the same device as the model
mel = whisper.log_mel_spectrogram(head_audio).to(model.device)

# detect the spoken language
_, probs = model.detect_language(mel)
print(f"Detected language: {max(probs, key=probs.get)}")

result = model.transcribe(audio,verbose=False)

# print the recognized text
# print(result["text"])
# print(result["segments"])

res_dict=result["segments"]

transcribe_dir=os.path.join(dir_path, f"whisper_{time_stamp}.txt")
# open file in write mode
with open(transcribe_dir, 'w+', encoding='utf-8') as f:
    f.write(result["text"])

