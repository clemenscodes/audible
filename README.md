# Audible

This repository contains a script to download your Audible library.

## Setup

Clone this repository

```sh
git clone https://github.com/clemenscodes/audible.git
cd audible
```

Get in the nix development shell.

```sh
nix develop -c $SHELL
```

Now authenticate with Audible.

```sh
audible quickstart
```

After authentication, you can now download your Audible library.

```sh
audible-download-library
```
