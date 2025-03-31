{
  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-unstable";
    };
  };
  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};
  in {
    packages = {
      ${system} = {
        audible-download-library = pkgs.writeShellApplication {
          name = "audible-download-library";
          runtimeInputs = [
            pkgs.audible-cli
            self.packages.${system}.audible-download-book
          ];
          text = ''
            audible_download_library() {
                echo "Exporting library..."
                audible library export --format "$AUDIBLE_FORMAT" --output "$AUDIBLE_LIBRARY"

                echo "Collecting ASINs of books..."
                tail -n +2 "$AUDIBLE_LIBRARY" | awk '{print $1}' > "$AUDIBLE_ASINS"

                if [ -f "$AUDIBLE_DOWNLOADED_ASINS" ]; then
                    rm -f "$AUDIBLE_DOWNLOADED_ASINS"
                fi

                download_books() {
                    touch "$AUDIBLE_DOWNLOADED_ASINS"

                    if [ -f "$AUDIBLE_MISSING_ASINS" ]; then
                        rm -f "$AUDIBLE_MISSING_ASINS"
                    fi

                    while IFS= read -r asin || [[ -n "$asin" ]]; do
                        if ! grep -qFx "$asin" "$AUDIBLE_DOWNLOADED_ASINS"; then
                            echo "$asin" >> "$AUDIBLE_MISSING_ASINS"
                        fi
                    done < "$AUDIBLE_ASINS"

                    if [ ! -f "$AUDIBLE_MISSING_ASINS" ]; then
                        return 0
                    fi

                    while IFS= read -r asin || [[ -n "$asin" ]]; do
                        audible-download-book "$asin"
                        echo "$asin" >> "$AUDIBLE_DOWNLOADED_ASINS"
                    done < "$AUDIBLE_MISSING_ASINS"

                    return 1
                }

                while ! download_books; do
                    echo "Checking for more books..."
                done

                echo "All books downloaded successfully!"
            }

            audible_download_library
          '';
        };
        audible-download-book = pkgs.writeShellApplication {
          name = "audible-download-book";
          runtimeInputs = [
            pkgs.audible-cli
            pkgs.aaxtomp3
            self.packages.${system}.audible-download-asin
            self.packages.${system}.audible-get-authcode
          ];
          excludeShellChecks = ["SC2181" "SC2317"];
          text = ''
            audible_download_book() {
                local asin
                local book
                local transcoded_aax
                local opus_highest_quality_level
                local aax_file
                local authcode

                asin="$1"
                book="$AUDIBLE_BOOKS/$asin"
                transcoded_aax="$book/transcoded"
                opus_highest_quality_level="10"

                if [ ! -d "$book" ]; then
                    echo "Downloading book with ASIN: $asin..."
                    audible-download-asin "$asin"

                    if [ ! -d "$book" ]; then
                        echo "Download failed for ASIN: $asin. Skipping."
                        return 1
                    fi
                fi

                if [ -d "$transcoded_aax" ]; then
                    echo "Book with ASIN $asin was already transcoded. Skipping."
                    return 0
                fi

                if [ ! -f "$AUDIBLE_AUTHCODE" ]; then
                    echo "Fetching Audible authcode..."
                    audible-get-authcode

                    if [ ! -f "$AUDIBLE_AUTHCODE" ]; then
                        echo "Failed to get Audible authcode."
                        return 1
                    fi
                fi

                authcode="$(cat "$AUDIBLE_AUTHCODE")"

                echo "Searching for audio file in $book..."
                aax_file="$(find "$book" -maxdepth 1 -type f -name "*.aax" -o -name "*.aaxc" | head -n 1)"

                if [ -z "$aax_file" ]; then
                    echo "No valid audio file found. Skipping."
                    return 1
                fi

                echo "Validating audio file..."
                aaxtomp3 --authcode "$authcode" --validate "$aax_file"

                if [ "$?" -ne 0 ]; then
                    echo "Validation failed. Skipping."
                    return 1
                fi

                echo "Creating backup of audio file..."
                mkdir -p "$transcoded_aax"
                cp "$aax_file" "$aax_file.bak"

                echo "Converting audio file to Opus format..."
                aaxtomp3 \
                    --authcode "$authcode" \
                    --use-audible-cli-data \
                    --opus \
                    --single \
                    --level "$opus_highest_quality_level" \
                    --loglevel 2 \
                    --no-clobber \
                    --target_dir "$book" \
                    --complete_dir "$transcoded_aax" \
                    "$aax_file"

                if [ "$?" -ne 0 ]; then
                    echo "Conversion failed."
                    return 1
                fi

                echo "Conversion complete for ASIN $asin."
                return 0
            }

            audible_download_book "$1"
          '';
        };
        audible-download-asin = pkgs.writeShellApplication {
          name = "audible-download-asin";
          runtimeInputs = [pkgs.audible-cli];
          excludeShellChecks = ["SC2317"];
          text = ''
            audible_download_asin() {
                local asin
                local book
                local retries

                asin="$(grep "$1" "$AUDIBLE_ASINS" | head -n1)"
                book="$AUDIBLE_BOOKS/$asin"
                retries=3

                if [ ! -d "$book" ]; then
                    mkdir -p "$book"
                fi

                for ((i = 1; i <= retries; i++)); do
                    echo "Attempt $i: Downloading book with ASIN $asin to $book"

                    audible download \
                        --output-dir "$book" \
                        --asin "$asin" \
                        --aax-fallback \
                        --quality best \
                        --pdf \
                        --cover \
                        --cover-size 1215 \
                        --chapter \
                        --annotation \
                        --no-confirm \
                        --overwrite \
                        --ignore-errors \
                        --jobs "$(nproc)" \
                        --filename-mode config \
                        --timeout 300 \
                        --ignore-podcasts

                    if find "$book" -maxdepth 1 -type f \( -name "*.aax" -o -name "*.aaxc" \) &>/dev/null; then
                        echo "Successfully downloaded book with ASIN $asin"
                        echo "$asin" >> "$AUDIBLE_DOWNLOADED_ASINS"
                        return 0
                    else
                        echo "Download failed for ASIN $asin. Retrying..."
                    fi
                done

                echo "Failed to download book with ASIN $asin after $retries attempts."
                return 1
            }

            audible_download_asin "$1"
          '';
        };
        audible-get-authcode = pkgs.writeShellApplication {
          name = "audible-get-authcode";
          runtimeInputs = [pkgs.audible-cli];
          text = ''
            echo "Getting audible authcode..."
            audible activation-bytes > "$AUDIBLE_AUTHCODE"
          '';
        };
        audible-export-books = pkgs.writeShellApplication {
          name = "audible-export-books";
          runtimeInputs = [pkgs.audible-cli];
          text = ''
            audible_export_books() {
                BOOKS="$XDG_PUBLICSHARE_DIR/books"

                mkdir -p "$BOOKS"

                echo "Exporting books to $BOOKS..."

                cp -r --preserve=mode,timestamps "$AUDIBLE_BOOKS"/* "$BOOKS"

                for book in "$BOOKS"/*; do
                    if [ -d "$book" ]; then
                        find "$book" -maxdepth 1 -type f \( -name "*.aax" -o -name "*.aaxc" \) -delete
                        if [ -d "$book/transcode" ]; then
                            rm -rf "$book/transcode"
                        fi
                    fi
                done
            }

            audible_export_books
          '';
        };
      };
    };
    devShells = {
      ${system} = {
        default = pkgs.mkShell {
          buildInputs = [
            pkgs.audible-cli
            pkgs.aaxtomp3
            self.packages.${system}.audible-download-asin
            self.packages.${system}.audible-download-library
            self.packages.${system}.audible-download-book
            self.packages.${system}.audible-get-authcode
            self.packages.${system}.audible-export-books
          ];
          shellHook = ''
            export AUDIBLE_CONFIG_DIR="$(pwd)/.audible"
            export AUDIBLE_ASINS="$AUDIBLE_CONFIG_DIR/asins"
            export AUDIBLE_DOWNLOADED_ASINS="$AUDIBLE_CONFIG_DIR/downloaded_asins"
            export AUDIBLE_MISSING_ASINS="$AUDIBLE_CONFIG_DIR/missing_asins"
            export AUDIBLE_FORMAT="tsv"
            export AUDIBLE_LIBRARY="$AUDIBLE_CONFIG_DIR/library.$AUDIBLE_FORMAT"
            export AUDIBLE_BOOKS="$AUDIBLE_CONFIG_DIR/books"
            export AUDIBLE_AUTHCODE="$AUDIBLE_CONFIG_DIR/authcode"

            mkdir -p $AUDIBLE_BOOKS
          '';
        };
      };
    };
  };
}
