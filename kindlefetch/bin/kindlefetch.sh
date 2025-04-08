#!/bin/sh

# Variables
SCRIPT_DIR=$(dirname "$(readlink "$0")")  # BusyBox lacks -f, so no canonical path
CONFIG_FILE="$SCRIPT_DIR/.kindlefetch_config"
VERSION_FILE="$SCRIPT_DIR/.version"

KINDLE_DOCUMENTS="/mnt/us/documents"

UPDATE_AVAILABLE=false

# Check if running on a Kindle
if ! [ -f "/etc/prettyversion.txt" ] && ! [ -d "/mnt/us" ] && ! pgrep lipc-daemon >/dev/null; then
    echo "Error: This script must run on a Kindle device." >&2
    exit 1
fi

sanitize_filename() {
    echo "$1" | sed -e 's/[^[:alnum:]\._-]/_/g' -e 's/ /_/g'
}

get_json_value() {
    echo "$1" | grep "\"$2\":\"" | sed "s/.*\"$2\":\"\([^\"]*\)\".*/\1/" && return
    echo "$1" | grep "\"$2\":" | sed "s/.*\"$2\":\([^,}]*\).*/\1/"
}

ensure_config_dir() {
    config_dir=$(dirname "$CONFIG_FILE")
    [ -d "$config_dir" ] || mkdir -p "$config_dir"
}

cleanup() {
    rm -f /tmp/kindle_books.list \
          /tmp/kindle_folders.list \
          /tmp/search_results.json \
          /tmp/last_search_*
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        . "$CONFIG_FILE"
    else
        first_time_setup
    fi
}

get_version() {
    api_response=$(curl -s -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/justrals/KindleFetch/commits") || {
        echo "Warning: Failed to fetch version from GitHub API" >&2
        echo "unknown"
        return
    }

    latest_sha=$(echo "$api_response" | grep '"sha":' | head -n 1 | cut -d'"' -f4 | cut -c1-7)
    echo "$latest_sha" > "$VERSION_FILE"
    load_version
}

load_version() {
    if [ -f "$VERSION_FILE" ]; then
        cat "$VERSION_FILE"
    else
        echo "Version file wasn't found!"
        sleep 2
        echo "Creating version file"
        sleep 2
        get_version
    fi
}

check_for_updates() {
    current_sha=$(load_version)

    latest_sha=$(curl -s -H "Accept: application/vnd.github.v3+json" \
        -H "Cache-Control: no-cache" \
        "https://api.github.com/repos/justrals/KindleFetch/commits?per_page=1" | \
        grep '"sha":' | head -n 1 | cut -d'"' -f4 | cut -c1-7)

    if [ -n "$latest_sha" ] && [ "$current_sha" != "$latest_sha" ]; then
        UPDATE_AVAILABLE=true
        return 0
    else
        return 1
    fi
}

save_config() {
    echo "KINDLE_DOCUMENTS=\"$KINDLE_DOCUMENTS\"" > "$CONFIG_FILE"
}

first_time_setup() {
    clear
    echo "
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
    
    echo "Enter your Kindle documents directory [default: $KINDLE_DOCUMENTS]: "
    read user_input
    if [ -n "$user_input" ]; then
        KINDLE_DOCUMENTS="$user_input"
    fi
    
    save_config
}

settings_menu() {
    while true; do
        clear
        echo "
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
        echo "1. Documents directory: $KINDLE_DOCUMENTS"
        echo "2. Check for updates"
        echo "3. Back to main menu"
        echo ""
        echo "Choose option: "
        read choice
        
        case "$choice" in
            1)
                echo "Enter new documents directory: "
                read new_dir
                if [ -n "$new_dir" ]; then
                    KINDLE_DOCUMENTS="$new_dir"
                    save_config
                fi
                ;;
            2)  
                check_for_updates
                if [ "$UPDATE_AVAILABLE" = true ]; then
                    echo "Update is available! Would you like to update? [y/N]: "
                    read confirm
                    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                        echo "Installing update..."
                        if curl -s https://justrals.github.io/KindleFetch/install/install_kindle.sh | sh; then
                            echo "Update installed successfully!"
                            UPDATE_AVAILABLE=false
                            VERSION=$(load_version)
                            sleep 2
                        else
                            echo "Failed to install update"
                            sleep 2
                        fi
                    fi
                else
                    echo "You're up-to-date!"
                    sleep 2
                fi
                ;;
            3) break ;;
            *) 
                echo "Invalid option"
                sleep 2
                ;;
        esac
    done
}

display_books() {
    clear
    echo "
  _____                     _     
 / ____|                   | |    
| (___   ___  __ _ _ __ ___| |__  
 \___ \ / _ \/ _\` | '__/ __| '_ \\ 
 ____) |  __/ (_| | | | (__| | | |
|_____/ \___|\__,_|_|  \___|_| |_|
"
    echo "--------------------------------"
    echo ""
    
    count=$(echo "$1" | grep '"title":' | wc -l)
    i=0
    while [ $i -lt $count ]; do
        book_info=$(echo "$1" | awk -v i=$i 'BEGIN{RS="{"; FS="}"} NR==i+2{print $0}')
        title=$(get_json_value "$book_info" "title")
        author=$(get_json_value "$book_info" "author")
        format=$(get_json_value "$book_info" "format")
        
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
    echo "1-$count: Select book | q: Quit"
    echo ""
}

list_local_books() {
    current_dir="${1:-$KINDLE_DOCUMENTS}"
    clear
    echo "
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

    printf "Are you sure you want to delete '$book_file'? [y/N] "
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

    printf "Are you sure you want to delete '$dir_path' and all its contents? [y/N] "
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
    query="$1"
    page="${2:-1}"
    
    if [ -z "$query" ]; then
        printf "Enter search query: "
        read query
        [ -z "$query" ] && {
            echo "Search query cannot be empty"
            return 1
        }
    fi
    
    echo "Searching for '$query' (page $page)..."
    
    encoded_query=$(echo "$query" | sed 's/ /+/g')
    search_url="https://annas-archive.org/search?q=${encoded_query}&page=${page}"
    
    html_content=$(curl -s -H "User-Agent: Mozilla/5.0" "$search_url")
    
    last_page=$(echo "$html_content" | sed -n 's/.*page=\([0-9]\+\)".*/\1/p' | sort -nr | head -n 1)
    [ -z "$last_page" ] && last_page=1
    
    has_prev="false"
    [ "$page" -gt 1 ] && has_prev="true"
    
    has_next="false"
    [ "$page" -lt "$last_page" ] && has_next="true"

    echo "$query" > /tmp/last_search_query
    echo "$page" > /tmp/last_search_page
    echo "$last_page" > /tmp/last_search_last_page
    echo "$has_next" > /tmp/last_search_has_next
    echo "$has_prev" > /tmp/last_search_has_prev
    
    books=$(echo "$html_content" | awk '
        BEGIN {
            RS="<div class=\"h-\\[110px\\] flex flex-col justify-center \">";
            FS=">";
            print "["
            book_count = 0
        }
        NR > 1 {
            link = ""; md5 = ""; title = ""; author = ""; format = "null"
            
            if ($0 ~ /<a href="\/md5\//) {
                link_start = index($0, "/md5/")
                link_end = index(substr($0, link_start), "\"")
                if (link_end > 0) {
                    link = substr($0, link_start, link_end - 1)
                    md5 = substr(link, 6, 32)
                }
            }
            
            if ($0 ~ /<h3 class=/) {
                title_start = index($0, "<h3")
                title_part = substr($0, title_start)
                title_start = index(title_part, ">") + 1
                title_end = index(title_part, "</h3>")
                if (title_end > 0) {
                    title = substr(title_part, title_start, title_end - title_start)
                    gsub(/^[ \t]+|[ \t]+$/, "", title)
                    gsub(/"/, "\\\"", title)
                    gsub(/•/, "\\u2022", title)
                }
            }
            
            if ($0 ~ /<div class=.*italic/) {
                author_start = index($0, "italic")
                author_part = substr($0, author_start)
                author_start = index(author_part, ">") + 1
                author_end = index(author_part, "</div>")
                if (author_end > 0) {
                    author = substr(author_part, author_start, author_end - author_start)
                    gsub(/^[ \t]+|[ \t]+$/, "", author)
                    gsub(/"/, "\\\"", author)
                }
            }
            
            if ($0 ~ /text-gray-500">/) {
                format_start = index($0, "text-gray-500\">") + 15
                format_part = substr($0, format_start)
                format_end = index(format_part, "<")
                if (format_end > 0) {
                    format_line = substr(format_part, 1, format_end - 1)
                    if (match(format_line, /\.([a-z0-9]+),/)) {
                        format = substr(format_line, RSTART + 1, RLENGTH - 2)
                        format = "\"" format "\""
                    }
                }
            }
            
            if (title != "") {
                if (book_count > 0) printf ",\n"
                printf "  {\"author\":\"%s\",\"format\":%s,\"md5\":\"%s\",\"title\":\"%s\",\"url\":\"https://annas-archive.org%s\"}", 
                    author, format, md5, title, link
                book_count++
            }
        }
        END { print "\n]" }
    ')
    
    echo "$books" > /tmp/search_results.json
}

download_book() {
    index=$1
    
    if [ ! -f "/tmp/search_results.json" ]; then
        echo "Error: No search results found" >&2
        return 1
    fi
    
    book_info=$(awk -v i="$index" 'BEGIN{RS="\\{"; FS="\\}"} NR==i+1{print $1}' /tmp/search_results.json)
    [ -z "$book_info" ] && {
        echo "Invalid selection" >&2
        return 1
    }
    
    md5=$(echo "$book_info" | sed -n 's/.*"md5":"\([^"]*\)".*/\1/p')
    title=$(echo "$book_info" | sed -n 's/.*"title":"\([^"]*\)".*/\1/p')
    author=$(echo "$book_info" | sed -n 's/.*"author":"\([^"]*\)".*/\1/p')
    format=$(echo "$book_info" | sed -n 's/.*"format":"\([^"]*\)".*/\1/p')
    
    echo "Downloading: $title"
    
    clean_title=$(echo "$title" | tr -cd '[:alnum:] ._-')
    book_folder="$KINDLE_DOCUMENTS/$clean_title"
    mkdir -p "$book_folder" || {
        echo "Error: Failed to create folder '$book_folder'" >&2
        return 1
    }

    libgen_content=$(curl -s -H "User-Agent: Mozilla/5.0" "https://libgen.li/ads.php?md5=$md5") || {
        echo "Error: Failed to fetch Libgen page" >&2
        return 1
    }
    
    download_link=$(echo "$libgen_content" | sed -n 's/.*href="\([^"]*get\.php[^"]*\)".*/\1/p' | head -n 1)
    [ -z "$download_link" ] && {
        echo "Error: No download link found" >&2
        return 1
    }

    temp_file="$book_folder/temp_$md5"
    echo "Progress:"
    
    for retry in 1 2 3; do
        if curl -f -L -C - \
                -o "$temp_file" \
                -H "User-Agent: Mozilla/5.0" \
                -H "Referer: https://libgen.li/" \
                "https://libgen.li/$download_link"; then
            echo "Download completed successfully!"
            break
        else
            if [ $retry -eq 3 ]; then
                echo "Error: Download failed after 3 attempts" >&2
                rm -f "$temp_file"
                return 1
            fi
            echo "Retrying ($retry/3)..."
            sleep 2
        fi
    done

    file_type=$(dd if="$temp_file" bs=4 count=1 2>/dev/null | hexdump -v -e '1/1 "%02X"')
    case "$file_type" in
        25504446*) extension="pdf" ;;
        45707562*) extension="epub" ;;
        4D6F6269*) extension="mobi" ;;
        415A5733*) extension="azw3" ;;
        *) extension="${format:-bin}" ;;
    esac

    final_file="$book_folder/$clean_title.$extension"
    
    if [ -f "$final_file" ]; then
        counter=1
        while [ -f "$book_folder/$clean_title-$counter.$extension" ]; do
            counter=$((counter + 1))
        done
        final_file="$book_folder/$clean_title-$counter.$extension"
    fi

    mv "$temp_file" "$final_file" || {
        echo "Error moving file" >&2
        return 1
    }

    echo "Saved to: $final_file"
    return 0
}

# Main menu
main_menu() {
    load_config
    check_for_updates
    
    while true; do
        clear
        printf "
 _  ___           _ _      ______   _       _     
| |/ (_)         | | |    |  ____| | |     | |    
| ' / _ _ __   __| | | ___| |__ ___| |_ ___| |__  
|  < | | '_ \\ / _\` | |/ _ \\  __/ _ \\ __/ __| '_ \\ 
| . \\| | | | | (_| | |  __/ | |  __/ || (__| | | |
|_|\\_\\_|_| |_|\\__,_|_|\\___|_|  \\___|\\__\\___|_| |_|
                                                
$(load_version) | https://github.com/justrals/KindleFetch                                               
\n"
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
        printf "Choose option: "
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
                        books=$(cat /tmp/search_results.json 2>/dev/null)
                        count=$(echo "$books" | grep -c '"title":')
                        
                        display_books "$books" "$current_page" "$has_prev" "$has_next" "$last_page"
                        
                        printf "Enter choice: "
                        read choice
                        
                        case "$choice" in
                            [qQ])
                                break
                                ;;
                            [pP])
                                if [ "$has_prev" = "true" ]; then
                                    new_page=$((current_page - 1))
                                    search_books "$query" "$new_page"
                                else
                                    echo "Already on first page"
                                    sleep 2
                                fi
                                ;;
                            [nN])
                                if [ "$has_next" = "true" ]; then
                                    new_page=$((current_page + 1))
                                    search_books "$query" "$new_page"
                                else
                                    echo "Already on last page"
                                    sleep 2
                                fi
                                ;;
                            *)
                                case "$choice" in
                                    *[!0-9]*)
                                        echo "Invalid input"
                                        sleep 2
                                        ;;
                                    *)
                                        if [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
                                            download_book "$choice"
                                            printf "Press Enter to continue..."
                                            read
                                        else
                                            echo "Invalid selection (must be between 1 and $count)"
                                            sleep 2
                                        fi
                                        ;;
                                esac
                                ;;
                        esac
                    done
                fi
                ;;
            2)
                current_dir="$KINDLE_DOCUMENTS"
                while true; do
                    if list_local_books "$current_dir"; then
                        folders_count=$(wc -l < /tmp/kindle_folders.list 2>/dev/null)
                        books_count=$(wc -l < /tmp/kindle_books.list 2>/dev/null)
                        total_items=$((folders_count + books_count))
                        
                        printf "Enter choice: "
                        read choice
                        
                        case "$choice" in
                            [qQ])
                                break
                                ;;
                            [nN])
                                current_dir=$(dirname "$current_dir")
                                ;;
                            [dD])
                                printf "Enter directory number to delete: "
                                read dir_num
                                if echo "$dir_num" | grep -q '^[0-9]\+$'; then
                                    if [ "$dir_num" -le "$folders_count" ]; then
                                        delete_directory "$dir_num"
                                    else
                                        echo "Invalid directory number"
                                        sleep 2
                                    fi
                                fi
                                ;;
                            *)
                                if echo "$choice" | grep -q '^[0-9]\+$'; then
                                    if [ "$choice" -ge 1 ] && [ "$choice" -le "$total_items" ]; then
                                        if [ "$choice" -le "$folders_count" ]; then
                                            current_dir=$(sed -n "${choice}p" /tmp/kindle_folders.list)
                                        else
                                            file_index=$((choice - folders_count))
                                            delete_book "$file_index"
                                        fi
                                    else
                                        echo "Invalid selection (must be between 1 and $total_items)"
                                        sleep 2
                                    fi
                                else
                                    echo "Invalid input"
                                    sleep 2
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
                    if curl -s https://justrals.github.io/KindleFetch/install/install_kindle.sh | sh; then
                        echo "Update installed successfully!"
                        UPDATE_AVAILABLE=false
                        VERSION=$(load_version)
                        sleep 2
                    else
                        echo "Failed to install update"
                        sleep 2
                    fi
                fi
                ;;
            *)
                echo "Invalid option"
                sleep 2
                ;;
        esac
    done
}

# Start the application
trap cleanup EXIT
main_menu