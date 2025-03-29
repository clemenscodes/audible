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
        audible-download-asin = pkgs.writeShellApplication {
          name = "audible-download-asin";
          runtimeInputs = [
            pkgs.audible-cli
            self.packages.${system}.audible-convert-book
          ];
          text = ''
            ASIN="$1"
            BOOK="$AUDIBLE_BOOKS/$ASIN"

            if [ ! -d "$BOOK" ]; then
              mkdir -p "$BOOK"

              echo "Downloading book with ASIN $ASIN to $BOOK"

              audible download \
                --output-dir "$BOOK" \
                --asin "$ASIN" \
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

              echo "Finished downloading book with ASIN $ASIN"
            else
              echo "Book with ASIN $ASIN already exists at $BOOK. Skipping."
            fi
          '';
        };
        audible-convert-book = pkgs.writeShellApplication {
          name = "audible-convert-book";
          runtimeInputs = [
            pkgs.audible-cli
            pkgs.aaxtomp3
            pkgs.eza
            pkgs.ripgrep
            self.packages.${system}.audible-get-authcode
          ];
          excludeShellChecks = [];
          text = ''
            ASIN="$1"
            BOOK="$AUDIBLE_BOOKS/$ASIN"
            TRANSCODED_AAX="$BOOK/transcode"
            OPUS_HIGHEST_QUALITY_LEVEL="10"

            if [ ! -d "$BOOK" ]; then
              audible-download-asin "$ASIN"
            fi

            if [ ! -d "$BOOK" ]; then
              echo "Failed to download book with ASIN $ASIN. Aborting."
              exit 1
            fi

            echo "Converting book at $BOOK"

            if [ ! -f "$AUDIBLE_AUTHCODE" ]; then
              audible-get-authcode
            fi

            if [ ! -f "$AUDIBLE_AUTHCODE" ]; then
              echo "Failed to get audible authcode at $AUDIBLE_AUTHCODE"
              exit 1
            fi

            AAX_FILE="$(eza \
              --absolute \
              --no-permissions \
              --no-filesize \
              --no-user \
              --no-time \
              --no-git \
              -1 \
              "$BOOK" | rg ".(aax|aaxc)$"
            )"

            AAX_FILE_BACKUP="$AAX_FILE.bak"

            echo "Checking for AAX file $AAX_FILE"
            if [ ! -f "$AAX_FILE" ]; then
              echo "No AAX or AAXC file found. Skipping"
            else
              echo "Validating AAX file $AAX_FILE..."
              aaxtomp3 \
                --authcode "$(cat "$AUDIBLE_AUTHCODE")" \
                --validate \
                "$AAX_FILE"

              echo "Backing up AAX file to $AAX_FILE_BACKUP"
              mkdir -p "$TRANSCODED_AAX"
              cp "$AAX_FILE" "$AAX_FILE_BACKUP"

              echo "Converting AAX files of the book at $BOOK to Opus format"
              aaxtomp3 \
                --authcode "$(cat "$AUDIBLE_AUTHCODE")" \
                --use-audible-cli-data \
                --opus \
                --single \
                --level "$OPUS_HIGHEST_QUALITY_LEVEL" \
                --loglevel 2 \
                --no-clobber \
                --target_dir "$BOOK" \
                --complete_dir "$TRANSCODED_AAX" \
                "$AAX_FILE"
            fi
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
        audible-download-library = pkgs.writeShellApplication {
          name = "audible-download-library";
          runtimeInputs = [
            pkgs.audible-cli
            self.packages.${system}.audible-download-asin
          ];
          text = ''
            echo "Exporting library..."
            audible library export --format "$AUDIBLE_FORMAT" --output "$AUDIBLE_LIBRARY"

            echo "Collecting ASIN of books..."
            tail -n +2 "$AUDIBLE_LIBRARY" | awk '{print $1}' > "$AUDIBLE_ASINS"

            echo "Downloading library..."
            while IFS= read -r asin; do
              audible-download-asin "$asin"
            done < "$AUDIBLE_ASINS"

            echo "Finished downloading library"
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
            self.packages.${system}.audible-convert-book
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
