# TARS CLI

A powerful, pipeline-friendly command-line tool to query Google's Gemini API directly from your terminal.

It can be used to quickly get explanations, ask for shell commands (which you can choose to execute safely), and acts as a generic AI utility.

## Features
- **Smart Command Generation**: Automatically builds commands to fulfill your prompt that execute correctly on your specific OS and shell.
- **Explain Code & Concepts**: Get simplified explanations with no excessive boilerplate straight to your terminal output.
- **Pipeline Support**: Pipe text into `tars` like you would with tools like `grep` or `jq`.
- **Interactive Execution**: Safely prompts if you wish to run generated bash commands or even save them to an alias for later use.
- **Sudo & Risk Detection**: Points out operations which involve `sudo` or other potentially destructive actions before you verify them.

## Requirements
- `curl`
- `jq`
- A [Gemini API Key](https://aistudio.google.com/app/apikey)

## Installation

1. Copy the script or clone this repository
2. Make the script executable
```bash
chmod +x tars.sh
```
3. Move the file somewhere in your `$PATH`, like `/usr/local/bin`:
```bash
sudo mv tars.sh /usr/local/bin/@
```
4. Set up your Gemini API Key as an environment variable (add this to your `.bashrc` or `.zshrc`):
```bash
export GEMINI_API_KEY="your_api_key_here"
```

## Usage
Simply ask a question right in the terminal:
```bash
@ list all files larger than 1gb in the current directory
```

### Piping Input
You can pipe text through standard input directly into your query:
```bash
cat Dockerfile | @ what does this file do?
```
```bash
ls -la | grep "error" | @ summarize these log files
```

### Passing Flags
By default, the script points to `gemini-2.5-flash-lite`. For detailed or complex logic, pass the `--pro` flag to invoke `gemini-2.5-flash`.
```bash
@ --pro write a complex python script that scrapes a website
```

## License
MIT
