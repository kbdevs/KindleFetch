<img src="https://github.com/user-attachments/assets/f0769d12-61dd-4f2f-91e0-79f8b0a302bb" width="30vw">
<img src="https://github.com/user-attachments/assets/e9a2dd94-7a63-4472-9b0b-cfc00763e628" width="30vw">
<img src="https://github.com/user-attachments/assets/31ec799c-c2be-4701-99d9-b6085b896729" width="30vw">

# KindleFetch

Simple CLI for downloading books to your Kindle without a computer.

## Prerequisites

**Your Kindle must be jailbroken before proceeding!**  
If it's not, follow [this comprehensive guide](https://kindlemodding.org/) first.

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

### On Your Server

1. **Install dependencies**:
   ```bash
   sudo apt update
   sudo apt install python3 python3-pip git
   ```

2. **Clone the repository and set up the environment**:
   ```bash
   git clone https://github.com/justrals/KindleFetch.git
   cd KindleFetch/server
   
   python3 -m venv venv
   source venv/bin/activate
   
   pip3 install -r requirements.txt
   ```

3. **Run the script**:
   ```bash
   python3 kindlefetch_server.py
   ```

   Expected output:
   ```bash
   (venv) root@ubuntu:~/KindleFetch/server# python3 kindlefetch_server.py 
    * Serving Flask app 'kindlefetch_server'
    * Debug mode: off
   WARNING: This is a development server. Do not use it in a production deployment.
    * Running on all addresses (0.0.0.0)
    * Running on http://127.0.0.1:5000
    * Running on http://XXX.XXX.XXX.XX:5000
   Press CTRL+C to quit
   ```

   > **Note**: During KindleFetch setup, use your server's IP address where indicated.
