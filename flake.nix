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
            echo "Exporting library..."
            audible library export --format "$AUDIBLE_FORMAT" --output "$AUDIBLE_LIBRARY"

            echo "Collecting ASIN of books..."
            tail -n +2 "$AUDIBLE_LIBRARY" | awk '{print $1}' > "$AUDIBLE_ASINS"

            echo "Downloading library..."

            while IFS= read -r asin; do
              audible-download-book "$asin"
            done < "$AUDIBLE_ASINS"

            echo "Finished downloading library"
          '';
        };
        audible-download-book = pkgs.writeShellApplication {
          name = "audible-download-book";
          runtimeInputs = [
            pkgs.audible-cli
            pkgs.aaxtomp3
            pkgs.eza
            self.packages.${system}.audible-download-asin
            self.packages.${system}.audible-get-authcode
          ];
          excludeShellChecks = ["SC2317"];
          text = ''
            audible_download_book() {
              local asin
              local book
              local aax_file
              local aax_file_backup

              asin="$(grep "$1" "$AUDIBLE_ASINS" | head -n1)"
              book="$AUDIBLE_BOOKS/$asin"

              transcoded_aax="$book/transcoded"
              OPUS_HIGHEST_QUALITY_LEVEL="10"

              if [ ! -d "$book" ]; then
                audible-download-asin "$asin"
              fi

              if [ ! -d "$book" ]; then
                echo "Failed to download book with ASIN $asin. Skipping."
                return
              fi

              if [ -d "$transcoded_aax" ]; then
                echo "Book with ASIN $asin was already transcoded. Skipping."
                return
              fi

              if [ ! -f "$AUDIBLE_AUTHCODE" ]; then
                audible-get-authcode
              fi

              if [ ! -f "$AUDIBLE_AUTHCODE" ]; then
                echo "Failed to get audible authcode at $AUDIBLE_AUTHCODE."
                exit 1
              fi

              aax_file="$(eza \
                --absolute \
                --no-permissions \
                --no-filesize \
                --no-user \
                --no-time \
                --no-git \
                -1 \
                "$book" | grep ".aax"
              )" || aax_file=""

              aax_file_backup="$aax_file.bak"

              echo "Checking for AAX file $aax_file"
              if [ ! -f "$aax_file" ]; then
                echo "No AAX or AAXC file found. Skipping."
              else
                echo "Validating AAX file $aax_file..."
                aaxtomp3 \
                  --authcode "$(cat "$AUDIBLE_AUTHCODE")" \
                  --validate \
                  "$aax_file"

                echo "Backing up AAX file to $aax_file_backup"
                mkdir -p "$transcoded_aax"
                cp "$aax_file" "$aax_file_backup"

                echo "Converting AAX or AAXC file of the book at $book to Opus format"
                aaxtomp3 \
                  --authcode "$(cat "$AUDIBLE_AUTHCODE")" \
                  --use-audible-cli-data \
                  --opus \
                  --single \
                  --level "$OPUS_HIGHEST_QUALITY_LEVEL" \
                  --loglevel 2 \
                  --no-clobber \
                  --target_dir "$book" \
                  --complete_dir "$transcoded_aax" \
                  "$aax_file"
              fi
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

              asin="$(grep "$1" "$AUDIBLE_ASINS" | head -n1)"
              book="$AUDIBLE_BOOKS/$asin"

              if [ ! -d "$book" ]; then
                mkdir -p "$book"

                echo "Downloading book with ASIN $asin to $book"

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
                  --ignore-podcasts

                echo "Finished downloading book with ASIN $asin"
              else
                echo "Book with ASIN $asin already exists at $book. Skipping."
              fi
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
          ];
          shellHook = ''
            export AUDIBLE_CONFIG_DIR="$(pwd)/.audible"
            export AUDIBLE_ASINS="$AUDIBLE_CONFIG_DIR/asins"
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
