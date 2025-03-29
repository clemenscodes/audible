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
          runtimeInputs = [pkgs.audible-cli];
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
            else
              echo "Book with ASIN $ASIN already exists at $BOOK. Skipping."
            fi
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
          ];
          shellHook = ''
            export AUDIBLE_CONFIG_DIR="$(pwd)/.audible"
            export AUDIBLE_ASINS="$AUDIBLE_CONFIG_DIR/asins"
            export AUDIBLE_FORMAT="tsv"
            export AUDIBLE_LIBRARY="$AUDIBLE_CONFIG_DIR/library.$AUDIBLE_FORMAT"
            export AUDIBLE_BOOKS="$AUDIBLE_CONFIG_DIR/books"

            mkdir -p $AUDIBLE_BOOKS
          '';
        };
      };
    };
  };
}
