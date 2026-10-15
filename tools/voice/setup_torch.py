"""Put the CUDA build of torch under Chatterbox: pip gives the CPU build on Windows by default.

Reinstalls the torch and torchaudio versions Chatterbox asked for, from PyTorch's CUDA index.
Run by voice.bat setup, after `pip install chatterbox-tts`."""
import subprocess
import sys
from importlib.metadata import version

tv, av = version("torch").split("+")[0], version("torchaudio").split("+")[0]
for cu in ("cu124", "cu126", "cu128", "cu121"):
    print("Trying torch %s / torchaudio %s for %s ..." % (tv, av, cu))
    r = subprocess.call([sys.executable, "-m", "pip", "install", "--force-reinstall", "--no-deps",
                         "torch==" + tv, "torchaudio==" + av, "--index-url", "https://download.pytorch.org/whl/" + cu])
    if r == 0:
        break
else:
    sys.exit("No CUDA build of torch %s found. Chatterbox will run on the CPU, very slowly." % tv)
r = subprocess.run([sys.executable, "-c", "import torch; print(torch.cuda.is_available())"], capture_output=True, text=True)
if r.stdout.strip() != "True":
    sys.exit("torch is installed but can't see the GPU. Update the NVIDIA driver and run setup again.")
