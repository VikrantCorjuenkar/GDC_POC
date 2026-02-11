import os
import datetime
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload

# --- CONFIGURATION ---
# 1. ID of the Folder in Google Drive (Found in the URL of the folder: drive.google.com/drive/folders/THIS_ID_HERE)
FOLDER_ID = 'YOUR_GOOGLE_DRIVE_FOLDER_ID_HERE' 

# 2. Path to your Service Account Key
KEY_FILE = 'scripts/service_account.json'

# 3. Path to Scan Results
SCAN_DIR = 'scanResults'
# ---------------------

def authenticate():
    creds = service_account.Credentials.from_service_account_file(
        KEY_FILE, scopes=['https://www.googleapis.com/auth/drive'])
    return build('drive', 'v3', credentials=creds)

def upload_files():
    if not os.path.exists(SCAN_DIR):
        print(f"❌ Scan directory '{SCAN_DIR}' not found.")
        return

    service = authenticate()
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M")

    print(f"☁️  Uploading results to Google Drive (Folder ID: {FOLDER_ID})...")

    # Loop through all files in scanResults
    for filename in os.listdir(SCAN_DIR):
        file_path = os.path.join(SCAN_DIR, filename)
        
        # Only upload files (skip directories)
        if os.path.isfile(file_path):
            # Create a unique name: "Apex_Scan.csv" -> "Apex_Scan_2023-10-27_10-00.csv"
            name, ext = os.path.splitext(filename)
            new_filename = f"{name}_{timestamp}{ext}"

            file_metadata = {
                'name': new_filename,
                'parents': [FOLDER_ID]
            }
            
            media = MediaFileUpload(file_path, resumable=True)
            
            try:
                file = service.files().create(body=file_metadata, media_body=media, fields='id').execute()
                print(f"   ✅ Uploaded: {new_filename} (ID: {file.get('id')})")
            except Exception as e:
                print(f"   ❌ Failed to upload {filename}: {e}")

if __name__ == '__main__':
    upload_files()