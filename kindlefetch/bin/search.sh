#!/bin/sh

display_books() {
    draw_header "Search" "Choose a result to download"

    local books="$1"
    local page="$2"
    local has_prev="$3"
    local has_next="$4"
    local last_page="$5"

    local count
    count="$(echo "$books" | grep -E '"title"[[:space:]]*:|^title=' | wc -l | tr -d ' ')"

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

parse_lgli_books() {
    awk -v base_url="$LGLI_URL" '
    function clean_text(value) {
        gsub(/\r/, "", value)
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
    function href_text(cell, href_part, value) {
        value = cell
        sub(".*href=\"" href_part "[^\"]*\"[^>]*>", "", value)
        sub(/<\/a>.*/, "", value)
        return clean_text(value)
    }
    function reset_record() {
        title = ""; author = ""; format = ""; md5 = ""; description = ""; col = 0
    }
    function emit_record() {
        if (title != "" && md5 != "" && !seen[md5]) {
            description = language
            if (year != "") {
                description = description " " year
            }
            if (size != "") {
                description = description " " size
            }
            gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", description)
            seen[md5] = 1
            if (count > 0) {
                printf ",\n"
            }
            print "  {"
            print "author=" json_escape(author)
            print "format=" json_escape(format)
            print "md5=" md5
            print "title=" json_escape(title)
            print "url=" base_url "/ads.php?md5=" md5
            print "description=" json_escape(description)
            printf "}"
            count++
        }
    }
    BEGIN {
        print "["
        count = 0
        inrow = 0
        reset_record()
    }
    /<\/tr>/ && inrow {
        emit_record()
        inrow = 0
    }
    /<tr>/ {
        inrow = 1
        reset_record()
    }
    inrow && /<td/ {
        col++
        cell = $0
        while (cell !~ /<\/td>/ && getline more > 0) {
            cell = cell "\n" more
        }

        if (col == 1 && cell ~ /href="edition.php/) {
            title = href_text(cell, "edition.php")
        } else if (col == 2) {
            author = clean_text(cell)
        } else if (col == 4) {
            year = clean_text(cell)
        } else if (col == 5) {
            language = clean_text(cell)
        } else if (col == 7) {
            size = clean_text(cell)
        } else if (col == 8) {
            format = tolower(clean_text(cell))
            sub(/[^a-z0-9].*/, "", format)
        }

        if (md5 == "" && match(cell, /ads\.php\?md5=[a-f0-9][a-f0-9]*/)) {
            md5 = substr(cell, RSTART + 12, 32)
        }

    }
    END {
        if (inrow) {
            emit_record()
        }
        print "\n]"
    }'
}

search_lgli_books() {
    query="$1"
    page="$2"
    encoded_query="$3"
    html_file="$4"

    [ -z "$LGLI_URL" ] && return 1

    search_url="$LGLI_URL/index.php?req=$encoded_query&columns%5B%5D=t&columns%5B%5D=a&columns%5B%5D=s&columns%5B%5D=p&columns%5B%5D=y&columns%5B%5D=i&columns%5B%5D=ser&columns%5B%5D=md5&objects%5B%5D=f&topics%5B%5D=l&res=25&filesuns=all"
    if [ "$page" -gt 1 ]; then
        search_url="$search_url&page=$page"
    fi
    echo "Fetching $search_url..."

    if fetch_url "$search_url" "$html_file"; then
        books="$(parse_lgli_books < "$html_file")"
        parsed_count="$(echo "$books" | grep -E '"title"[[:space:]]*:|^title=' | wc -l | tr -d ' ')"
        [ "$parsed_count" != "0" ] && return 0
    fi

    return 1
}

search_books() {
    local query="$1"
    local page="${2:-1}"
    local retry_mirrors="${3:-true}"
    
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
    local html_file="$TMP_DIR/kindlefetch_search.html"
    local html_content=""
    local parsed_count=0
    local tried_urls=""
    local search_url=""

    for candidate_url in "$ANNAS_URL" $ANNAS_MIRROR_URLS; do
        [ -z "$candidate_url" ] && continue
        case " $tried_urls " in
            *" $candidate_url "*) continue ;;
        esac
        tried_urls="$tried_urls $candidate_url"
        search_url="$candidate_url/search?page=${page}&q=${encoded_query}${filters}"
        echo "Fetching $search_url..."

        if fetch_url "$search_url" "$html_file"; then
            html_content="$(cat "$html_file")"
        else
            html_content=""
        fi

        ANNAS_URL="$candidate_url"
        books="$(printf "%s\n" "$html_content" | awk -v base_url="$ANNAS_URL" '
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
        function emit_record() {
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
        function reset_record() {
            title = ""; author = ""; md5 = ""; format = ""; description = ""
        }
        function attr_value(line, attr, start, value) {
            start = index(line, attr "=\"")
            if (!start) {
                return ""
            }
            value = substr(line, start + length(attr) + 2)
            sub(/".*/, "", value)
            return clean_text(value)
        }
        BEGIN {
            print "["
            count = 0
            reset_record()
        }
        /<div class="flex  *pt-3/ {
            emit_record()
            reset_record()
        }
        {
            if (md5 == "" && match($0, /href="\/md5\/[a-f0-9][a-f0-9]*/)) {
                md5 = substr($0, RSTART+11, 32)
            }

            if (title == "" && index($0, "text-violet-900") && index($0, "data-content=")) {
                title = attr_value($0, "data-content")
            }

            if (author == "" && index($0, "text-amber-900") && index($0, "data-content=")) {
                author = attr_value($0, "data-content")
            }

            if (format == "" && index($0, "font-mono")) {
                lower_line = tolower(clean_text($0))
                n = split(lower_line, parts, ".")
                if (n > 1) {
                    ext = parts[n]
                    sub(/[^a-z0-9].*/, "", ext)
                    if (ext == "epub" || ext == "pdf" || ext == "mobi" || ext == "azw3" || ext == "txt" || ext == "fb2" || ext == "djvu" || ext == "cbz" || ext == "cbr") {
                        format = ext
                    }
                }
            }

            if (description == "" && index($0, "text-gray-800") && index($0, "font-semibold") && index($0, "text-sm")) {
                description = clean_text($0)
            }

            title = json_escape(title)
            author = json_escape(author)
            description = json_escape(description)
        }
        END {
            emit_record()
            print "\n]"
        }'
        )"
        parsed_count="$(echo "$books" | grep -E '"title"[[:space:]]*:|^title=' | wc -l | tr -d ' ')"
        if [ "$parsed_count" != "0" ]; then
            save_config
            break
        fi

        [ "$retry_mirrors" != "true" ] && break
    done

    if [ "$parsed_count" = "0" ]; then
        echo "Anna returned no usable results; trying LibGen..."
        if search_lgli_books "$query" "$page" "$encoded_query" "$html_file"; then
            html_content="$(cat "$html_file")"
            save_config
        fi
    fi
    
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
    
    echo "$books" > "$TMP_DIR"/search_results.json

    if [ "$parsed_count" = "0" ]; then
        echo "No results found."
        echo "Last URL: $search_url"
        echo "Downloaded bytes: $(wc -c < "$html_file" 2>/dev/null | tr -d ' ')"
        [ -s "$TMP_DIR"/kindlefetch_fetch_error ] && {
            echo "Fetch error:"
            head -3 "$TMP_DIR"/kindlefetch_fetch_error
        }
        echo "Saved response to $html_file"
        pause
        return 1
    fi

    while true; do
        local query="$(cat "$TMP_DIR"/last_search_query 2>/dev/null)"
        local current_page="$(cat "$TMP_DIR"/last_search_page 2>/dev/null || echo 1)"
        local last_page="$(cat "$TMP_DIR"/last_search_last_page 2>/dev/null || echo 1)"
        local has_next="$(cat "$TMP_DIR"/last_search_has_next 2>/dev/null || echo "false")"
        local has_prev="$(cat "$TMP_DIR"/last_search_has_prev 2>/dev/null || echo "false")"
        local books="$(cat "$TMP_DIR"/search_results.json 2>/dev/null)"
        local count="$(echo "$books" | grep -E '"title"[[:space:]]*:|^title=' | wc -l | tr -d ' ')"

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
                                                    stty -echo 2>/dev/null || true
                                                    read -r zlib_password
                                                    stty echo 2>/dev/null || true
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
