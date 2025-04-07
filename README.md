<img src="https://github.com/user-attachments/assets/f0769d12-61dd-4f2f-91e0-79f8b0a302bb" width="200px">

# KindleFetch

<a href="https://github.com/justrals/KindleFetch"><img src="https://img.shields.io/github/stars/justrals/KindleFetch" height="25px"></a>

Simple CLI for downloading books from [Anna's Archive](https://annas-archive.org/) directly to your Kindle without a computer.

## Prerequisites

**Your Kindle must be jailbroken before proceeding!**  
If it's not, follow [this guide](https://kindlemodding.org/) first.

## Installation

### On Your Kindle Device

1. **Install kterm**:
   - Download the latest release from [kterm's releases page](https://github.com/bfabiszewski/kterm/releases)
   - Unzip the archive to the `extensions` directory in your Kindle's root

2. **Launch KUAL** (Kindle Unified Application Launcher) and open the newly added kterm application

3. **Run the installation command** in kterm:
   ```bash
   curl https://justrals.github.io/KindleFetch/install/install_kindle.sh | sh
   ```

4. **Complete the setup**:
   - Wait for the installation to finish (you should see a success message)
   - Type `exit` to close kterm
   - You should now see a new "KindleFetch" option in KUAL