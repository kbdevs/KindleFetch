#!/bin/sh

display_books() {
    draw_header "Search" "Choose a result to download"

    local books="$1"
    local page="$2"
    local has_prev="$3"
    local has_next="$4"
    local last_page="$5"

    local count
    count="$(echo "$books" | grep -E '"title"[[:space:]]*:|^title=' | wc -l)"

    local start=0
    local end=$((count - 1))

    i=$start
    while [ "$i" -le "$end" ]; do
        book_info="$(echo "$books" | awk -v i=$i 'BEGIN{RS="\\{"; FS="\\}"} NR==i+2{print $1}')"

        title="$(get_json_value "$book_info" "title")"
        author="$(get_json_value "$book_info" "author")"
        format="$(get_json_value "$book_info" "format")"
        description="$(get_json_value "$book_info" "description")"

        if [ "$COMPACT_OUTPUT" != true ]; then
            printf "%2d. %s\n" "$((i+1))" "$title"
            [ -n "$author" ] && [ "$author" != "null" ] && echo "    by $author"
            [ -n "$format" ] && [ "$format" != "null" ] && echo "    $format"
            [ -n "$description" ] && [ "$description" != "null" ] && echo "    $description"
            echo ""
        else
            printf "%2d. %s by %s in %s format\n" \
                "$((i+1))" "$title" "$author" "$format"
            echo ""
        fi

        i=$((i + 1))
    done

    local items_on_page="$count"

    echo "--------------------------------"
    echo ""
    echo "Page $page of $last_page"
    echo ""

    [ "$has_prev" = true ] && echo -n "p: Previous page | "
    echo -n "t[1-$last_page]: Select page | "
    [ "$has_next" = true ] && echo -n "n: Next page | "
    [ "$items_on_page" -gt 0 ] && echo "1-$items_on_page: Select book | q: Quit" || echo "q: Quit"
    echo ""
}

search_books() {
    local query="$1"
    local page="${2:-1}"
    
    if [ -z "$query" ]; then
        echo -n "Enter search query: "
        read -r query
        [ -z "$query" ] && {
            echo "Search query cannot be empty"
            return 1
        }
    fi
    
    echo "Searching for '$query' (page $page)..."

    local filters=""
    if [ -f "$SCRIPT_DIR"/tmp/current_filter_params ]; then
        filters=$(cat "$SCRIPT_DIR/tmp/current_filter_params")
    fi
    
    local encoded_query=$(echo "$query" | sed 's/ /+/g')
    local search_url="$ANNAS_URL/search?page=${page}&q=${encoded_query}${filters}"
    local html_content="$(curl -L -s -A "Mozilla/5.0" "$search_url") || html_content=$(curl -L -s -A "Mozilla/5.0" -x "$PROXY_URL" "$search_url")"
    
    local last_page="$(echo "$html_content" | grep -o 'page=[0-9]\+"' | sort -t= -k2 -nr | head -1 | cut -d= -f2 | tr -d '"')"
    [ -z "$last_page" ] && last_page=1
    
    local has_prev=false
    [ "$page" -gt 1 ] && has_prev=true
    
    local has_next=false
    [ "$page" -lt "$last_page" ] && has_next=true

    echo "$query" > "$TMP_DIR"/last_search_query
    echo "$page" > "$TMP_DIR"/last_search_page
    echo "$last_page" > "$TMP_DIR"/last_search_last_page
    echo "$has_next" > "$TMP_DIR"/last_search_has_next
    echo "$has_prev" > "$TMP_DIR"/last_search_has_prev
    
    local books="$(printf "%s\n" "$html_content" | sed 's/<div class="flex  *pt-3/<KF_RECORD/g' | awk -v base_url="$ANNAS_URL" '
        function clean_text(value) {
            gsub(/<script[^>]*>[^<]*(<[^>]*>[^<]*)*<\/script>/, "", value)
            gsub(/<[^>]*>/, "", value)
            gsub(/&amp;/, "\\&", value)
            gsub(/&#39;|&apos;/, "", value)
            gsub(/&quot;/, "\"", value)
            gsub(/&nbsp;/, " ", value)
            gsub(/&[#a-zA-Z0-9]+;/, "", value)
            gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", value)
            gsub(/[ \t\r\n][ \t\r\n]+/, " ", value)
            return value
        }
        function json_escape(value) {
            gsub(/\\/, "\\\\", value)
            gsub(/"/, "\\\"", value)
            return value
        }
        BEGIN {
            RS = "<KF_RECORD"
            q = sprintf("%c", 34)
            print "["
            count = 0
        }
        NR > 1 {
            title = ""; author = ""; md5 = ""; format = ""; description = ""
        
            # md5
            if (match($0, /href="\/md5\/[a-f0-9][a-f0-9]*/)) {
                md5 = substr($0, RSTART+11, 32)
            }
        
            # title: prefer the visible result link, fall back to cover metadata.
            if (match($0, /<a href="\/md5\/[a-f0-9][a-f0-9]*"[^>]*js-vim-focus[^>]*>[^<]+<\/a>/)) {
                title = clean_text(substr($0, RSTART, RLENGTH))
            } else if (match($0, /<div class="font-bold text-violet-900 line-clamp-\[5\]" data-content="[^"]+"/)) {
                block = substr($0, RSTART, RLENGTH)
                if (match(block, /data-content="[^"]+"/)) {
                    title = substr(block, RSTART+14, RLENGTH-15)
                    title = clean_text(title)
                }
            }
        
            # author: first visible author search link, fall back to cover metadata.
            if (match($0, /<a href="\/search\?q=[^"]+"[^>]*><span[^>]*><\/span>[^<]+<\/a>/)) {
                author = clean_text(substr($0, RSTART, RLENGTH))
            } else if ($0 ~ /<div[^>]*class="[^"]*font-bold[^"]*text-amber-900[^"]*line-clamp-\[2\][^"]*"/) {
                if (match($0, /<div[^>]*class="[^"]*font-bold[^"]*text-amber-900[^"]*line-clamp-\[2\][^"]*" data-content="[^"]+"/)) {
                    block = substr($0, RSTART, RLENGTH)
                    if (match(block, /data-content="[^"]+"/)) {
                        author = substr(block, RSTART+14, RLENGTH-15)
                        author = clean_text(author)
                    }
                }
            }
        
            # format
            if (match($0, /font-mono">[^<]+\.(epub|pdf|mobi|azw3|txt|fb2|djvu|cbz|cbr)/)) {
                line = substr($0, RSTART, RLENGTH)
                if (match(line, /\.(epub|pdf|mobi|azw3|txt|fb2|djvu|cbz|cbr)/)) {
                    format = substr(line, RSTART+1, RLENGTH-1)
                }
            } else if (match($0, /<div class="text-gray-800[^>]*>[^<]+/)) {
                line = substr($0, RSTART, RLENGTH)
                if (match(line, />[^<]+/)) {
                    content = substr(line, RSTART+1, RLENGTH-1)
                    n = split(content, parts, " · ")
                    if (n >= 2) {
                        format = parts[2]
                    }
                }
            }
            
            # description
            if (match($0, /<div[^>]*class="[^"]*text-gray-800[^"]*font-semibold[^"]*text-sm[^"]*leading-\[1\.2\][^"]*mt-2[^"]*"[^>]*>.*?<\/div>/)) {
                line = substr($0, RSTART, RLENGTH)

                description = clean_text(line)
            }
        
            # emoji replacements
            gsub(/🚀/, "Partner Server", description)
            gsub(/📗|📘|📕|📰|💬|📝|🤨|🎶|✅/, "", description)
        
            title = json_escape(title)
            author = json_escape(author)
            description = json_escape(description)
        
            if (title != "" && md5 != "" && !seen[md5]) {
                seen[md5] = 1
                if (count > 0) {
                    printf ",\n"
                }
                print "  {"
                print "author=" author
                print "format=" format
                print "md5=" md5
                print "title=" title
                print "url=" base_url "/md5/" md5
                print "description=" description
                printf "}"
                count++
            }
        }
        END {
            print "\n]"
        }'
    )"
    
    echo "$books" > "$TMP_DIR"/search_results.json

    while true; do
        local query="$(cat "$TMP_DIR"/last_search_query 2>/dev/null)"
        local current_page="$(cat "$TMP_DIR"/last_search_page 2>/dev/null || echo 1)"
        local last_page="$(cat "$TMP_DIR"/last_search_last_page 2>/dev/null || echo 1)"
        local has_next="$(cat "$TMP_DIR"/last_search_has_next 2>/dev/null || echo "false")"
        local has_prev="$(cat "$TMP_DIR"/last_search_has_prev 2>/dev/null || echo "false")"
        local books="$(cat "$TMP_DIR"/search_results.json 2>/dev/null)"
        local count="$(echo "$books" | grep -E '"title"[[:space:]]*:|^title=' | wc -l)"

        display_books "$books" "$current_page" "$has_prev" "$has_next" "$last_page"
        
        echo -n "Enter choice: "
        read -r choice
        
        case "$choice" in
            [qQ])
                return 0
                ;;
            [pP])
                if [ "$has_prev" = true ]; then
                    new_page=$((current_page - 1))
                    search_books "$query" "$new_page"
                    return
                else
                    echo "Already on first page"
                    sleep 2
                fi
                ;;
            [nN])
                if [ "$has_next" = true ]; then
                    new_page=$((current_page + 1))
                    search_books "$query" "$new_page"
                    return
                else
                    echo "Already on last page"
                    sleep 2
                fi
                ;;
            t[0-9]*)
                page_number="${choice#t}"
                if echo "$page_number" | grep -qE '^[0-9]+$'; then
                    if [ "$page_number" -ge 1 ] && [ "$page_number" -le "$last_page" ]; then
                        if [ "$page_number" -ne "$current_page" ]; then
                            search_books "$query" "$page_number"
                            return
                        else
                            echo "You are already on page $current_page"
                            sleep 2
                        fi
                    else
                        echo "Page number out of range (1-$last_page)"
                        sleep 2
                    fi
                else
                    echo "Invalid input"
                    sleep 2
                fi
                ;;
            *)  
                if echo "$choice" | grep -qE '^[0-9]+$'; then
                    local items_on_page="$count"

                    if [ "$choice" -ge 1 ] && [ "$choice" -le "$items_on_page" ]; then
                        absolute_index=$(( choice - 1 ))

                        book_info="$(awk -v i=$absolute_index \
                            'BEGIN{RS="\\{"; FS="\\}"} NR==i+2{print $1}' \
                            "$TMP_DIR"/search_results.json)"

                        local md5="$(get_json_value "$book_info" "md5")"
                        local lgli_available=false
                        local zlib_available=false
                        [ -n "$md5" ] && [ -n "$LGLI_URL" ] && lgli_available=true
                        [ -n "$md5" ] && [ -n "$ZLIB_URL" ] && zlib_available=true

                        while true; do
                            if [ "$lgli_available" = false ] && [ "$zlib_available" = false ]; then
                                echo "There are no available sources for this book right now."
                            fi

                            if [ "$lgli_available" = true ]; then
                                echo "1. lgli"
                            fi
                            if [ "$zlib_available" = true ]; then
                                if [ "$ZLIB_AUTH" = true ]; then
                                    echo "2. zlib"
                                else
                                    echo "2. zlib (Authentication required)"
                                fi
                            fi
                            echo "3. Cancel download"

                            echo -n "Choose source to proceed with: "
                            read -r source_choice

                            case "$source_choice" in
                                1)
                                    if [ "$lgli_available" = true ]; then
                                        echo "Proceeding with lgli..."
                                        if ! lgli_download "$choice"; then
                                            echo "Download from lgli failed."
                                            sleep 2
                                        else
                                            break
                                        fi
                                    else
                                        echo "Invalid choice."
                                    fi
                                    ;;
                                2)
                                    if [ "$zlib_available" = true ]; then
                                        if [ "$ZLIB_AUTH" = true ]; then
                                            echo "Proceeding with zlib..."
                                            if ! zlib_download "$choice"; then
                                                echo "Download from zlib failed."
                                                sleep 2
                                            else
                                                break
                                            fi
                                        else
                                            echo
                                            echo -n "Do you want to sign into your zlib account? [Y/n]: "
                                            read -r zlib_login_choice
                                            echo

                                            if [ "$zlib_login_choice" = "n" ] || [ "$zlib_login_choice" = "N" ]; then
                                                ZLIB_AUTH=false
                                                save_config
                                            else
                                                while true; do
                                                    echo -n "Zlib email: "
                                                    read -r zlib_email
                                                    echo -n "Zlib password: "
                                                    read -s -r zlib_password
                                                    echo

                                                    if zlib_login "$zlib_email" "$zlib_password"; then
                                                        ZLIB_AUTH=true
                                                        save_config

                                                        printf "\n\nProceeding with zlib..."
                                                        if ! zlib_download "$choice"; then
                                                            echo "Download from zlib failed."
                                                            sleep 2
                                                        else
                                                            break 2
                                                        fi
                                                    else
                                                        echo -n "Zlib login failed. Do you want to try again? [Y/n]: "
                                                        read -r zlib_login_retry_choice
                                                        echo
                                                        
                                                        if [ "$zlib_login_retry_choice" = "n" ] || [ "$zlib_login_retry_choice" = "N" ]; then
                                                            ZLIB_AUTH=false
                                                            save_config
                                                            break
                                                        fi
                                                    fi
                                                done
                                            fi
                                        fi
                                    else
                                        echo "Invalid choice."
                                    fi
                                    ;;
                                3)
                                    break
                                    ;;
                                *)
                                    echo "Invalid choice."
                                    ;;
                            esac
                        done

                        pause
                    else
                        echo "Invalid selection (must be between 1 and $items_on_page)"
                        sleep 2
                    fi
                else
                    echo "Invalid input"
                    sleep 2
                fi
                ;;
        esac
    done
}
