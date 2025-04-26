# Morse Trainer

**A Bash-based Morse code trainer built with accessibility in mind.**

## About

Morse Trainer is a project born out of frustration — a frustration with the lack of accessible Morse code training software for blind users. After trying various tools (including some paid ones), and constantly running into barriers, I decided to create my own solution from scratch, using Bash.

This project is still in its early stages and far from perfect, but it’s already usable and slowly getting better. My hope is to build something that is minimal, accessible, and truly helpful for blind users who want to learn or practice Morse code using the terminal.

## Features

- Runs entirely in Bash — no GUI, no dependencies beyond core Linux utilities.
- Designed for screen reader compatibility.
- Initial support for training random letters and words in Morse.
- Focus on simplicity, clarity, and no unnecessary visual output.

### Running the Tool on macOS

To run this tool on macOS, you need to take a few additional steps. Some utilities that are standard on Linux systems are either missing or behave slightly differently on macOS. Follow these steps to set up the required environment:

1. **Install Homebrew**  
   Homebrew is a package manager for macOS that allows you to install the necessary tools.  
   [Download Homebrew](https://brew.sh/) and follow the installation instructions.

2. **Upgrade Bash**  
   macOS ships with an older version of Bash by default. To ensure compatibility with features like `declare`, upgrade Bash:  
   ```bash
   brew install bash
   ```

3. **Install SoX**  
   SoX is required for sound playback:  
   ```bash
   brew install sox
   ```

4. **Install Coreutils**  
   The `shuf` command (used in the script) is not available on macOS by default. Installing Coreutils provides this and other GNU utilities:  
   ```bash
   brew install coreutils
   ```

5. **Install GNU Sed**  
   The default `sed` on macOS behaves differently, especially when editing files directly. Install GNU Sed to ensure compatibility:  
   ```bash
   brew install gnu-sed
   ```

6. **Install GNU Grep**  
   The default `grep` on macOS lacks some features available in GNU Grep. Install it to ensure consistent behavior:  
   ```bash
   brew install grep
   ```

7. **Install All at Once**  
   Alternatively, you can install all the necessary tools in one command:  
   ```bash
   brew install coreutils gnu-sed grep
   ```

After completing these steps, the tool should work correctly on macOS. Happy testing!

## Feedback and Contributions

I’m especially interested in **constructive feedback**, accessibility improvements, and suggestions from other blind users or accessibility-conscious developers. Feel free to open an issue, start a discussion, or fork the repo and make a pull request.

If you're sighted and want to help: please remember this is primarily a tool for blind users. Fancy visuals are not the goal — clarity and usability via the terminal are.

## A Note from the Author

As a blind developer, I’ve often felt like we're an afterthought in software design. With Morse Trainer, I’m taking matters into my own hands — building something *by* and *for* people like me. If this helps even one person avoid the same frustration I’ve felt, it’s worth it.

**Richard Emling (DO9RE)**
