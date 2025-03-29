from flask import Flask, request, jsonify, send_from_directory, Response
import requests
from bs4 import BeautifulSoup
import subprocess
import os
import re
import urllib.parse
import magic
import threading
import time

app = Flask(__name__)

SERVER_DOWNLOAD_DIR = "books/"
os.makedirs(SERVER_DOWNLOAD_DIR, exist_ok=True)

downloads_in_progress = {}

def sanitize_filename(title):
    filename = re.sub(r'[^\w\-_\. ]', '_', title)
    return filename.replace(' ', '_')

def get_actual_file_type(filepath):
    mime = magic.Magic(mime=True)
    file_type = mime.from_file(filepath)
    
    mime_map = {
        'application/epub+zip': 'epub',
        'application/x-mobipocket-ebook': 'mobi',
        'application/vnd.amazon.ebook': 'azw3',
        'application/pdf': 'pdf',
        'text/plain': 'txt'
    }
    
    return mime_map.get(file_type, 'bin')

@app.route('/search', methods=['GET'])
def search():
    query = request.args.get('q')
    if not query:
        return jsonify({"error": "Missing query parameter"}), 400
    
    try:
        url = f"https://annas-archive.org/search?q={urllib.parse.quote(query)}"
        response = requests.get(url, headers={'User-Agent': 'Mozilla/5.0'})
        soup = BeautifulSoup(response.text, 'html.parser')
        books = []
        
        for item in soup.select('div.h-\\[110px\\], div.flex.flex-col'):
            try:
                title = item.find('h3').get_text(strip=True)
                author = item.find('div', class_='italic').get_text(strip=True)
                link = item.find('a')['href']
                md5 = link.split('/md5/')[1].split('/')[0] if '/md5/' in link else None
                format_span = item.find('span', class_='hidden md:inline')
                file_format = format_span.get_text(strip=True).lower() if format_span else None
                
                books.append({
                    'title': title,
                    'author': author,
                    'url': f'https://annas-archive.org{link}',
                    'md5': md5,
                    'format': file_format
                })
            except:
                continue
                
        return jsonify({"results": books})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

def download_file(md5, title, preferred_format, download_id):
    try:
        clean_title = sanitize_filename(title)
        libgen_url = f"https://libgen.li/ads.php?md5={md5}"
        response = requests.get(libgen_url)
        soup = BeautifulSoup(response.text, 'html.parser')
        
        download_link = None
        for a in soup.find_all('a', href=True):
            if 'get.php' in a['href']:
                download_link = f"https://libgen.li/{a['href']}"
                break
        
        if not download_link:
            downloads_in_progress.pop(download_id, None)
            return {"error": "Download link not found"}, 404
        
        temp_filepath = os.path.join(SERVER_DOWNLOAD_DIR, f"temp_{md5}")
        
        with requests.get(download_link, stream=True) as r:
            total_length = r.headers.get('content-length')
            if total_length is None:
                downloads_in_progress.pop(download_id, None)
                return {"error": "Failed to get content length"}, 500
            
            total_length = int(total_length)
            downloaded = 0
            
            with open(temp_filepath, 'wb') as f:
                for chunk in r.iter_content(chunk_size=4096):
                    if download_id not in downloads_in_progress:
                        return {"error": "Download cancelled"}, 400
                    f.write(chunk)
                    downloaded += len(chunk)
                    downloads_in_progress[download_id] = downloaded / total_length * 100
            
        actual_extension = get_actual_file_type(temp_filepath)
        final_extension = preferred_format if preferred_format and (actual_extension == 'bin' or preferred_format == actual_extension) else actual_extension
        
        filename = f"{clean_title}.{final_extension}"
        final_filepath = os.path.join(SERVER_DOWNLOAD_DIR, filename)
        
        os.rename(temp_filepath, final_filepath)
        os.chmod(final_filepath, 0o644)
        
        downloads_in_progress.pop(download_id, None)
        return {
            "filename": filename,
            "message": "File downloaded successfully",
            "actual_type": actual_extension,
            "final_extension": final_extension
        }, 200
    except Exception as e:
        downloads_in_progress.pop(download_id, None)
        return {"error": str(e)}, 500

@app.route('/download', methods=['POST'])
def download():
    data = request.json
    if not data or 'md5' not in data or 'title' not in data:
        return jsonify({"error": "Missing required fields"}), 400
    
    download_id = str(time.time())
    downloads_in_progress[download_id] = 0
    
    threading.Thread(target=download_file, args=(data['md5'], data['title'], data.get('format'), download_id)).start()
    
    return jsonify({"download_id": download_id}), 202

@app.route('/progress/<download_id>', methods=['GET'])
def progress(download_id):
    if download_id not in downloads_in_progress:
        return jsonify({"error": "Invalid download ID"}), 404
    
    progress = downloads_in_progress[download_id]
    return jsonify({"progress": progress}), 200

@app.route('/cancel/<download_id>', methods=['DELETE'])
def cancel_download(download_id):
    if download_id in downloads_in_progress:
        downloads_in_progress.pop(download_id, None)
        return jsonify({"message": "Download cancelled"}), 200
    return jsonify({"error": "Invalid download ID"}), 404

@app.route('/books/<path:filename>')
def serve_book(filename):
    return send_from_directory(SERVER_DOWNLOAD_DIR, filename)

@app.route('/delete', methods=['POST'])
def delete_book():
    data = request.json
    if not data or 'filename' not in data:
        return jsonify({"error": "Missing filename"}), 400
    
    filename = data['filename']
    filepath = os.path.join(SERVER_DOWNLOAD_DIR, filename)
    
    try:
        if os.path.exists(filepath):
            os.remove(filepath)
            return jsonify({"success": True, "message": f"Deleted {filename}"})
        return jsonify({"error": "File not found"}), 404
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)