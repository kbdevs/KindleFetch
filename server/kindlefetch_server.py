from flask import Flask, request, jsonify, send_from_directory
import requests
from bs4 import BeautifulSoup
import subprocess
import os
import re
import urllib.parse
import magic

app = Flask(__name__)

SERVER_DOWNLOAD_DIR = "books/"
os.makedirs(SERVER_DOWNLOAD_DIR, exist_ok=True)

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
    page = request.args.get('page', '1')
    
    if not query:
        return jsonify({"error": "Missing query parameter"}), 400
    
    try:
        url = f"https://annas-archive.org/search?q={urllib.parse.quote(query)}&page={page}"
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
        
        pagination = soup.select_one('nav[aria-label="Pagination"]')
        current_page = 1
        first_page = 1
        last_page = 1
        
        if pagination:
            page_links = pagination.select('a:not(.js-pagination-prev-page):not(.js-pagination-next-page)')
            
            if page_links:
                try:
                    first_page = int(page_links[0].get_text(strip=True))
                except:
                    pass
                
                try:
                    last_page = int(page_links[-1].get_text(strip=True))
                except:
                    pass
            
            current_link = pagination.select_one('a[aria-current="page"]')
            if current_link:
                try:
                    current_page = int(current_link.get_text(strip=True))
                except:
                    pass
        
        return jsonify({
            "results": books,
            "current_page": current_page,
            "first_page": first_page,
            "last_page": last_page,
            "has_prev": current_page > first_page,
            "has_next": current_page < last_page
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/download', methods=['POST'])
def download():
    data = request.json
    if not data or 'md5' not in data or 'title' not in data:
        return jsonify({"error": "Missing required fields"}), 400
    
    try:
        md5 = data['md5']
        title = data['title']
        clean_title = sanitize_filename(title)
        preferred_format = data.get('format')

        libgen_url = f"https://libgen.li/ads.php?md5={md5}"
        response = requests.get(libgen_url)
        soup = BeautifulSoup(response.text, 'html.parser')
        
        download_link = None
        for a in soup.find_all('a', href=True):
            if 'get.php' in a['href']:
                download_link = f"https://libgen.li/{a['href']}"
                break
        
        if not download_link:
            return jsonify({"error": "Download link not found"}), 404
        
        temp_filepath = os.path.join(SERVER_DOWNLOAD_DIR, f"temp_{md5}")
        
        subprocess.run([
            'wget',
            '-O', temp_filepath,
            '--user-agent=Mozilla/5.0',
            '--referer=https://libgen.li/',
            download_link
        ], check=True)
        
        actual_extension = get_actual_file_type(temp_filepath)
        final_extension = preferred_format if preferred_format and (actual_extension == 'bin' or preferred_format == actual_extension) else actual_extension
        
        filename = f"{clean_title}.{final_extension}"
        final_filepath = os.path.join(SERVER_DOWNLOAD_DIR, filename)
        
        os.rename(temp_filepath, final_filepath)
        os.chmod(final_filepath, 0o644)
        
        return jsonify({
            "filename": filename,
            "message": "File downloaded successfully",
            "actual_type": actual_extension,
            "final_extension": final_extension
        })
    except subprocess.CalledProcessError as e:
        return jsonify({"error": f"Download failed: {str(e)}"}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500

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
