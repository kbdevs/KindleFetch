#!/bin/sh

# Configuration file path
CONFIG_FILE="/mnt/us/documents/kindlefetch/bin/kindlefetch_config"

# Default values
SERVER_API=""
KINDLE_DOCUMENTS="/mnt/us/documents"

get_json_value() {
    echo "$1" | grep -o "\"$2\":\"[^\"]*\"" | sed "s/\"$2\":\"\([^\"]*\)\"/\1/"
}

ensure_config_dir() {
    config_dir=$(dirname "$CONFIG_FILE")
    if [ ! -d "$config_dir" ]; then
        mkdir -p "$config_dir"
    fi
}

# Load configuration if exists
load_config() {
    ensure_config_dir
    if [ -f "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE"
    else
        first_time_setup
    fi
}

# First time configuration
first_time_setup() {
    clear
    echo -e "
  _____      _               
 / ____|    | |              
| (___   ___| |_ _   _ _ __  
 \___ \ / _ \ __| | | | '_ \ 
 ____) |  __/ |_| |_| | |_) |
|_____/ \___|\__|\__,_| .__/ 
                      | |    
                      |_|    
"
    echo "Welcome to KindleFetch! Let's set up your configuration."
    echo ""
    
    echo -n "Enter your server API URL [example: http://161.128.167.197:5000]: "
    read user_input
    if [ -n "$user_input" ]; then
        SERVER_API="$user_input"
    fi
    
    echo -n "Enter your Kindle documents directory [default: $KINDLE_DOCUMENTS]: "
    read user_input
    if [ -n "$user_input" ]; then
        KINDLE_DOCUMENTS="$user_input"
    fi
    
    save_config
}

# Save configuration to file
save_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    echo "SERVER_API=\"$SERVER_API\"" > "$CONFIG_FILE"
    echo "KINDLE_DOCUMENTS=\"$KINDLE_DOCUMENTS\"" >> "$CONFIG_FILE"
}

# Settings menu
settings_menu() {
    while true; do
        clear
        echo -e "
  _____      _   _   _                 
 / ____|    | | | | (_)                
| (___   ___| |_| |_ _ _ __   __ _ ___ 
 \___ \ / _ \ __| __| | '_ \ / _\` / __|
 ____) |  __/ |_| |_| | | | | (_| \__ \\
|_____/ \___|\__|\__|_|_| |_|\__, |___/
                              __/ |    
                             |___/     
"
        echo "Current configuration:"
        echo "1. Server API URL: ${SERVER_API:-[not set]}"
        echo "2. Documents directory: $KINDLE_DOCUMENTS"
        echo "3. Back to main menu"
        echo ""
        echo -n "Choose option: "
        read choice
        
        case "$choice" in
            1)
                echo -n "Enter new server API URL: "
                read new_url
                SERVER_API="$new_url"
                save_config
                ;;
            2)
                echo -n "Enter new documents directory: "
                read new_dir
                if [ -n "$new_dir" ]; then
                    KINDLE_DOCUMENTS="$new_dir"
                    save_config
                fi
                ;;
            3)
                break
                ;;
            *)
                echo "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# Search menu
display_books() {
    clear
    echo -e "
  _____                     _     
 / ____|                   | |    
| (___   ___  __ _ _ __ ___| |__  
 \___ \ / _ \/ _\` | '__/ __| '_ \\ 
 ____) |  __/ (_| | | | (__| | | |
|_____/ \___|\__,_|_|  \___|_| |_|
"
    count=$(echo "$1" | grep -o '"title":' | wc -l)
    i=0
    
    while [ $i -lt $count ]; do
        book_info=$(echo "$1" | awk -v i=$i 'BEGIN{RS="\\{"; FS="\\}"} NR==i+2{print $1}')
        title=$(get_json_value "$book_info" "title")
        author=$(get_json_value "$book_info" "author")
        format=$(get_json_value "$book_info" "format")
        
        echo "$((i+1)). $title"
        echo "   by $author${format:+ (format: $format)}"
        i=$((i+1))
    done
    echo ""
}

# Local books menu
list_local_books() {
    clear
    echo -e "
 ____              _        
|  _ \            | |       
| |_) | ___   ___ | | _____ 
|  _ < / _ \ / _ \| |/ / __|
| |_) | (_) | (_) |   <\__ \\
|____/ \___/ \___/|_|\_\___/
"
    
    i=1
    > /tmp/kindle_books.list
    
    if [ ! -d "$KINDLE_DOCUMENTS" ]; then
        echo "Error: Documents directory '$KINDLE_DOCUMENTS' does not exist."
        return 1
    fi
    
    for file in "$KINDLE_DOCUMENTS"/*; do
        case "$file" in
            *.pdf|*.epub|*.mobi|*.azw3)
                filename=$(basename "$file")
                echo "$i. $filename"
                echo "$filename" >> /tmp/kindle_books.list
                i=$((i+1))
                ;;
        esac
    done
    
    if [ $i -eq 1 ]; then
        echo "No books found in your documents folder."
        return 1
    fi
    echo ""
}

delete_book() {
    index=$1
    book_file=$(sed -n "${index}p" /tmp/kindle_books.list 2>/dev/null)
    
    if [ -z "$book_file" ]; then
        echo "Invalid selection"
        return 1
    fi

    echo -n "Are you sure you want to delete '$book_file'? [y/N] "
    read confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        if rm -f "$KINDLE_DOCUMENTS/$book_file"; then
            echo "Book deleted successfully"
        else
            echo "Failed to delete book"
        fi
    else
        echo "Deletion canceled"
    fi
}

search_books() {
    if [ -z "$SERVER_API" ]; then
        echo "Error: Server API URL is not configured."
        return 1
    fi

    echo -n "Enter search query: "
    read query
    
    if [ -z "$query" ]; then
        echo "Search query cannot be empty"
        return 1
    fi
    
    response=$(curl -s -G "$SERVER_API/search" --data-urlencode "q=$query")
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to connect to server"
        return 1
    fi
    
    error=$(get_json_value "$response" "error")
    if [ -n "$error" ]; then
        echo "Error: $error"
        return 1
    fi
    
    # Extract results array
    results=$(echo "$response" | sed 's/.*"results":\[\(.*\)\].*/\1/' | sed 's/},{/}\n{/g')
    
    if [ -z "$results" ]; then
        echo "No books found!"
        return 1
    fi
    
    display_books "$results"
    echo "$results" > /tmp/anna_results.json
}

download_book() {
    if [ -z "$SERVER_API" ]; then
        echo "Error: Server API URL is not configured."
        return 1
    fi

    index=$1
    
    if [ ! -f "/tmp/results.json" ]; then
        echo "Error: No search results found"
        return 1
    fi
    
    book_info=$(awk -v i="$index" 'BEGIN{RS="\\{"; FS="\\}"} NR==i+1{print $1}' /tmp/anna_results.json)
    
    if [ -z "$book_info" ]; then
        echo "Invalid selection"
        return 1
    fi
    
    md5=$(get_json_value "$book_info" "md5")
    title=$(get_json_value "$book_info" "title")
    format=$(get_json_value "$book_info" "format")
    
    echo "Downloading: $title"
    
    download_data="{\"md5\":\"$md5\",\"title\":\"$title\""
    if [ -n "$format" ]; then
        download_data="$download_data,\"format\":\"$format\""
    fi
    download_data="$download_data}"
    
    response=$(curl -s -X POST "$SERVER_API/download" \
        -H "Content-Type: application/json" \
        -d "$download_data")
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to connect to server"
        return 1
    fi
    
    error=$(get_json_value "$response" "error")
    if [ -n "$error" ]; then
        echo "Download failed: $error"
        return 1
    fi
    
    filename=$(get_json_value "$response" "filename")
    actual_type=$(get_json_value "$response" "actual_type")
    final_extension=$(get_json_value "$response" "final_extension")
    
    echo "Detected type: $actual_type, saving as .$final_extension"
    
    if curl -s -o "$KINDLE_DOCUMENTS/$filename" "$SERVER_API/books/$filename"; then
        echo "Success! Saved to: $KINDLE_DOCUMENTS/$filename"
    
        delete_response=$(curl -s -X POST "$SERVER_API/delete" \
            -H "Content-Type: application/json" \
            -d "{\"filename\":\"$filename\"}")
        
        error=$(get_json_value "$delete_response" "error")
        if [ -n "$error" ]; then
            echo "Warning: Could not delete from server - $error"
        fi
    else
        echo "Transfer failed"
        return 1
    fi
}

cleanup() {
    rm -f /tmp/kindle_books.list
    rm -f /tmp/anna_results.json
}

# Main menu
main_menu() {
    load_config
    
    while true; do
        clear
        echo -e "
 _  ___           _ _      ______   _       _     
| |/ (_)         | | |    |  ____| | |     | |    
| ' / _ _ __   __| | | ___| |__ ___| |_ ___| |__  
|  < | | '_ \ / _\` | |/ _ \  __/ _ \ __/ __| '_ \\ 
| . \| | | | | (_| | |  __/ | |  __/ || (__| | | |
|_|\_\_|_| |_|\__,_|_|\___|_|  \___|\__\___|_| |_|
                                                
v1.0 | https://github.com/justrals/KindleFetch                                               
"
        echo "1. Search and download books"
        echo "2. List my books"
        echo "3. Settings"
        echo "4. Exit"
        echo ""
        echo -n "Choose option: "
        read choice
        
        case "$choice" in
            1)
                if search_books; then
                    while true; do
                        echo -n "Enter book number to download (q to go back): "
                        read book_choice
                        
                        case "$book_choice" in
                            [qQ])
                                break
                                ;;
                            *)
                                if echo "$book_choice" | grep -qE '^[0-9]+$'; then
                                    download_book "$book_choice"
                                else
                                    echo "Invalid input"
                                fi
                                ;;
                        esac
                    done
                fi
                ;;
            2)
                if list_local_books; then
                    while true; do
                        echo -n "Enter book number to delete (q to go back): "
                        read book_choice
                        
                        case "$book_choice" in
                            [qQ])
                                break
                                ;;
                            *)
                                if echo "$book_choice" | grep -qE '^[0-9]+$'; then
                                    delete_book "$book_choice"
                                    list_local_books || break
                                else
                                    echo "Invalid input"
                                fi
                                ;;
                        esac
                    done
                fi
                ;;
            3)
                settings_menu
                ;;
            4)
                cleanup
                exit 0
                ;;
            *)
                echo "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# Start the application
trap cleanup EXIT
main_menu
