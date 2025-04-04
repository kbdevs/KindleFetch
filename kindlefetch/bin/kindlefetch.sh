#!/bin/sh

# Configuration file path
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
CONFIG_FILE="$SCRIPT_DIR/kindlefetch_config"
VERSION_FILE="$SCRIPT_DIR/version"

# Default config values
SERVER_API=""
KINDLE_DOCUMENTS="/mnt/us/documents"

UPDATE_AVAILABLE=false

get_json_value() {
    echo "$1" | grep -o "\"$2\":\"[^\"]*\"" | sed "s/\"$2\":\"\([^\"]*\)\"/\1/" || \
    echo "$1" | grep -o "\"$2\":[^,}]*" | sed "s/\"$2\":\([^,}]*\)/\1/"
}

ensure_config_dir() {
    config_dir=$(dirname "$CONFIG_FILE")
    if [ ! -d "$config_dir" ]; then
        mkdir -p "$config_dir"
    fi
}

cleanup() {
    rm -f /tmp/kindle_books.list
    rm -f /tmp/search_results.json
}

# Load configuration if exists
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE"
    else
        first_time_setup
    fi
}

load_version() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE"
    else
        echo "Version file wasn't found!"
    fi
}

check_for_updates() {
    local current_version=$(load_version)
    local remote_version=$(curl -s -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/justrals/KindleFetch/commits" | \
        grep -o '"sha":' | wc -l)
    
    if [ -n "$remote_version" ] && [ "$remote_version" -gt "${current_version%%-*}" ]; then
        UPDATE_AVAILABLE=true
    fi
}

# Save configuration to file
save_config() {
    echo "SERVER_API=\"$SERVER_API\"" > "$CONFIG_FILE"
    echo "KINDLE_DOCUMENTS=\"$KINDLE_DOCUMENTS\"" >> "$CONFIG_FILE"
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
        echo "3. Check for updates"
        echo "4. Back to main menu"
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
                check_for_updates
                if [$UPDATE_AVAILABLE]; then
                    echo "Update is available! Would you like to update? [y/N]: "
                    read confirm

                    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                        echo "Installing update..."
                        if curl https://justrals.github.io/KindleFetch/install/install_kindle.sh | sh; then
                            echo "Update installed successfully!"
                            UPDATE_AVAILABLE=false
                            VERSION=$(load_version)
                            sleep 2
                        else
                            echo "Failed to install update"
                            sleep 2
                        fi
                    esac
                else
                    echo "You're up-to-date!"
                fi
                ;;
            4)
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
    echo "--------------------------------"
    echo ""
    count=$(echo "$1" | grep -o '"title":' | wc -l)
    i=0
    
    while [ $i -lt $count ]; do
        book_info=$(echo "$1" | awk -v i=$i 'BEGIN{RS="\\{"; FS="\\}"} NR==i+2{print $1}')
        title=$(get_json_value "$book_info" "title")
        author=$(get_json_value "$book_info" "author")
        format=$(get_json_value "$book_info" "format")
        
        title=$(echo "$title" | sed 's/\\u[0-9a-f]\{4\}//g')
        
        printf "%2d. %s\n" $((i+1)) "$title"
        [ -n "$author" ] && echo "    by $author"
        [ -n "$format" ] && echo "    Format: $format"
        i=$((i+1))
    done
    echo ""
    echo "--------------------------------"
    echo ""
    echo "Page $2 of $5"
    echo ""
    if [ "$3" = "true" ]; then
    echo -n "p: Previous page | "
    fi
    if [ "$4" = "true" ]; then
        echo -n "n: Next page | "
    fi
    echo -e "1-$count: Select book | q: Quit"
    echo ""
}

# Local books menu
list_local_books() {
    local current_dir="${1:-$KINDLE_DOCUMENTS}"
    clear
    echo -e "
 ____              _        
|  _ \            | |       
| |_) | ___   ___ | | _____ 
|  _ < / _ \ / _ \| |/ / __|
| |_) | (_) | (_) |   <\__ \\
|____/ \___/ \___/|_|\_\___/
"
    echo "Current directory: $current_dir"
    echo "--------------------------------"
    echo ""
    
    i=1
    > /tmp/kindle_books.list
    > /tmp/kindle_folders.list

    if [ ! -d "$current_dir" ]; then
        echo "Error: Directory '$current_dir' does not exist."
        return 1
    fi

    for item in "$current_dir"/*; do
        if [ -d "$item" ]; then
            foldername=$(basename "$item")
            echo "$i. $foldername/"
            echo "$item" >> /tmp/kindle_folders.list
            i=$((i+1))
        fi
    done

    for item in "$current_dir"/*; do
        if [ -f "$item" ]; then
            filename=$(basename "$item")
            extension="${filename##*.}"
            echo "$i. $filename"
            echo "$item" >> /tmp/kindle_books.list
            i=$((i+1))
        fi
    done
    
    if [ $i -eq 1 ]; then
        echo "No books or folders found."
        return 1
    fi
    
    echo ""
    echo "--------------------------------"
    echo "n: Go up to parent directory"
    echo "d: Delete directory"
    echo "q: Back to main menu"
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
        if rm -f "$book_file"; then
            echo "Book deleted successfully"
        else
            echo "Failed to delete book"
        fi
    else
        echo "Deletion canceled"
    fi
}

delete_directory() {
    index=$1
    dir_path=$(sed -n "${index}p" /tmp/kindle_folders.list 2>/dev/null)
    
    if [ -z "$dir_path" ]; then
        echo "Invalid selection"
        return 1
    fi

    echo -n "Are you sure you want to delete '$dir_path' and all its contents? [y/N] "
    read confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        if rm -rf "$dir_path"; then
            echo "Directory deleted successfully"
        else
            echo "Failed to delete directory"
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

    local query="$1"
    local page="${2:-1}"
    
    if [ -z "$query" ]; then
        echo -n "Enter search query: "
        read query
        if [ -z "$query" ]; then
            echo "Search query cannot be empty"
            return 1
        fi
    fi
    
    echo "Searching for '$query' (page $page)..."
    
    response=$(curl -s -G "$SERVER_API/search" --data-urlencode "q=$query" --data-urlencode "page=$page")
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to connect to server"
        return 1
    fi
    
    error=$(get_json_value "$response" "error")
    if [ -n "$error" ]; then
        echo "Error: $error"
        return 1
    fi
    
    results=$(echo "$response" | sed 's/.*"results":\[\(.*\)\].*/\1/' | sed 's/},{/}\n{/g')
    current_page=$(echo "$response" | grep -o '"current_page":[0-9]*' | cut -d: -f2)
    last_page=$(echo "$response" | grep -o '"last_page":[0-9]*' | cut -d: -f2)
    has_next=$(echo "$response" | grep -o '"has_next":true' | wc -l)
    has_prev=$(echo "$response" | grep -o '"has_prev":true' | wc -l)

    [ -z "$current_page" ] && current_page=1
    [ -z "$last_page" ] && last_page=1
    [ "$has_next" -gt 0 ] && has_next="true" || has_next="false"
    [ "$has_prev" -gt 0 ] && has_prev="true" || has_prev="false"

    if [ -z "$results" ]; then
        echo "No books found!"
        return 1
    fi
    
    echo "$query" > /tmp/last_search_query
    echo "$current_page" > /tmp/last_search_page
    echo "$last_page" > /tmp/last_search_last_page
    echo "$has_next" > /tmp/last_search_has_next
    echo "$has_prev" > /tmp/last_search_has_prev
    
    display_books "$results" "$current_page" "$has_prev" "$has_next" "$last_page"
    echo "$results" > /tmp/search_results.json
    return 0
}

download_book() {
    if [ -z "$SERVER_API" ]; then
        echo "Error: Server API URL is not configured."
        return 1
    fi

    index=$1
    
    if [ ! -f "/tmp/search_results.json" ]; then
        echo "Error: No search results found"
        return 1
    fi
    
    book_info=$(awk -v i="$index" 'BEGIN{RS="\\{"; FS="\\}"} NR==i+1{print $1}' /tmp/search_results.json)
    
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
    filename_without_type=${filename%.*}

    echo "$title is almost done transferring to your Kindle!"

    if [ ! -d "$KINDLE_DOCUMENTS" ]; then
        echo "Creating Kindle documents directory: $KINDLE_DOCUMENTS"
        mkdir -p "$KINDLE_DOCUMENTS"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to create directory $KINDLE_DOCUMENTS"
            return 1
        fi
    fi

    mkdir "$KINDLE_DOCUMENTS/$filename_without_type"

    if curl -s -o "$KINDLE_DOCUMENTS/$filename_without_type/$filename" "$SERVER_API/books/$filename"; then
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

# Main menu
main_menu() {
    load_config
    check_for_updates
    
    while true; do
        clear
        echo -e "
 _  ___           _ _      ______   _       _     
| |/ (_)         | | |    |  ____| | |     | |    
| ' / _ _ __   __| | | ___| |__ ___| |_ ___| |__  
|  < | | '_ \ / _\` | |/ _ \  __/ _ \ __/ __| '_ \\ 
| . \| | | | | (_| | |  __/ | |  __/ || (__| | | |
|_|\_\_|_| |_|\__,_|_|\___|_|  \___|\__\___|_| |_|
                                                
${load_version} | https://github.com/justrals/KindleFetch                                               
"
        if $UPDATE_AVAILABLE; then
            echo "Update available! Select option 5 to install."
            echo ""
        fi
        echo "1. Search and download books"
        echo "2. List my books"
        echo "3. Settings"
        echo "4. Exit"
        if $UPDATE_AVAILABLE; then
            echo "5. Install update"
        fi
        echo ""
        echo -n "Choose option: "
        read choice
        
        case "$choice" in
            1)
                if search_books; then
                    while true; do
                        query=$(cat /tmp/last_search_query 2>/dev/null)
                        current_page=$(cat /tmp/last_search_page 2>/dev/null || echo 1)
                        last_page=$(cat /tmp/last_search_last_page 2>/dev/null || echo 1)
                        has_next=$(cat /tmp/last_search_has_next 2>/dev/null || echo "false")
                        has_prev=$(cat /tmp/last_search_has_prev 2>/dev/null || echo "false")
                        count=$(cat /tmp/search_results.json | grep -o '"title":' | wc -l)
                        
                        echo -n "Enter choice: "
                        read book_choice
                        
                        case "$book_choice" in
                            [qQ])
                                break
                                ;;
                            [nN])
                                if [ "$has_next" = "true" ]; then
                                    search_books "$query" "$((current_page + 1))"
                                else
                                    echo "Already on last page (page $current_page of $last_page)"
                                    sleep 1
                                fi
                                ;;
                            [pP])
                                if [ "$has_prev" = "true" ]; then
                                    search_books "$query" "$((current_page - 1))"
                                else
                                    echo "Already on first page (page 1 of $last_page)"
                                    sleep 1
                                fi
                                ;;
                            *)
                                if echo "$book_choice" | grep -qE '^[0-9]+$'; then
                                    if [ "$book_choice" -ge 1 ] && [ "$book_choice" -le "$count" ]; then
                                        download_book "$book_choice"
                                    else
                                        echo "Invalid selection (must be between 1 and $count)"
                                        sleep 1
                                    fi
                                else
                                    echo "Invalid input"
                                    sleep 1
                                fi
                                ;;
                        esac
                    done
                fi
                ;;
            2)
                current_dir="$KINDLE_DOCUMENTS"
                while true; do
                    if list_local_books "$current_dir"; then
                        total_items=$(( $(wc -l < /tmp/kindle_folders.list 2>/dev/null) + $(wc -l < /tmp/kindle_books.list 2>/dev/null) ))
                        
                        echo -n "Enter choice: "
                        read choice
                        
                        case "$choice" in
                            [qQ])
                                break
                                ;;
                            [nN])
                                current_dir=$(dirname "$current_dir")
                                ;;
                            [dD])
                                echo -n "Enter directory number to delete: "
                                read dir_num
                                if echo "$dir_num" | grep -qE '^[0-9]+$'; then
                                    if [ "$dir_num" -le $(wc -l < /tmp/kindle_folders.list 2>/dev/null) ]; then
                                        delete_directory "$dir_num"
                                    else
                                        echo "Invalid directory number"
                                        sleep 1
                                    fi
                                fi
                                ;;
                            *)
                                if echo "$choice" | grep -qE '^[0-9]+$'; then
                                    if [ "$choice" -ge 1 ] && [ "$choice" -le "$total_items" ]; then
                                        if [ "$choice" -le $(wc -l < /tmp/kindle_folders.list 2>/dev/null) ]; then
                                            current_dir=$(sed -n "${choice}p" /tmp/kindle_folders.list)
                                        else
                                            file_index=$((choice - $(wc -l < /tmp/kindle_folders.list 2>/dev/null)))
                                            delete_book "$file_index"
                                        fi
                                    else
                                        echo "Invalid selection (must be between 1 and $total_items)"
                                        sleep 1
                                    fi
                                else
                                    echo "Invalid input"
                                    sleep 1
                                fi
                                ;;
                        esac
                    else
                        sleep 2
                        break
                    fi
                done
                ;;
            3)
                settings_menu
                ;;
            4)
                cleanup
                exit 0
                ;;
            5)
                if $UPDATE_AVAILABLE; then
                    echo "Installing update..."
                    if curl https://justrals.github.io/KindleFetch/install/install_kindle.sh | sh; then
                        echo "Update installed successfully!"
                        UPDATE_AVAILABLE=false
                        VERSION=$(load_version)
                        sleep 2
                    else
                        echo "Failed to install update"
                        sleep 2
                    fi
                else
                    echo "No update available"
                    sleep 1
                fi
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
