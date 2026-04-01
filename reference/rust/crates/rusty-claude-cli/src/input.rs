use std::io::{self, IsTerminal, Write};

use crossterm::cursor::MoveToColumn;
use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyModifiers};
use crossterm::queue;
use crossterm::style::Print;
use crossterm::terminal::{disable_raw_mode, enable_raw_mode, Clear, ClearType};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InputBuffer {
    buffer: String,
    cursor: usize,
}

impl InputBuffer {
    #[must_use]
    pub fn new() -> Self {
        Self {
            buffer: String::new(),
            cursor: 0,
        }
    }

    pub fn insert(&mut self, ch: char) {
        self.buffer.insert(self.cursor, ch);
        self.cursor += ch.len_utf8();
    }

    pub fn insert_newline(&mut self) {
        self.insert('\n');
    }

    pub fn backspace(&mut self) {
        if self.cursor == 0 {
            return;
        }

        let previous = self.buffer[..self.cursor]
            .char_indices()
            .last()
            .map_or(0, |(idx, _)| idx);
        self.buffer.drain(previous..self.cursor);
        self.cursor = previous;
    }

    pub fn move_left(&mut self) {
        if self.cursor == 0 {
            return;
        }
        self.cursor = self.buffer[..self.cursor]
            .char_indices()
            .last()
            .map_or(0, |(idx, _)| idx);
    }

    pub fn move_right(&mut self) {
        if self.cursor >= self.buffer.len() {
            return;
        }
        if let Some(next) = self.buffer[self.cursor..].chars().next() {
            self.cursor += next.len_utf8();
        }
    }

    pub fn move_home(&mut self) {
        self.cursor = 0;
    }

    pub fn move_end(&mut self) {
        self.cursor = self.buffer.len();
    }

    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.buffer
    }

    #[cfg(test)]
    #[must_use]
    pub fn cursor(&self) -> usize {
        self.cursor
    }

    pub fn clear(&mut self) {
        self.buffer.clear();
        self.cursor = 0;
    }
}

pub struct LineEditor {
    prompt: String,
}

impl LineEditor {
    #[must_use]
    pub fn new(prompt: impl Into<String>) -> Self {
        Self {
            prompt: prompt.into(),
        }
    }

    pub fn read_line(&self) -> io::Result<Option<String>> {
        if !io::stdin().is_terminal() || !io::stdout().is_terminal() {
            return self.read_line_fallback();
        }

        enable_raw_mode()?;
        let mut stdout = io::stdout();
        let mut input = InputBuffer::new();
        self.redraw(&mut stdout, &input)?;

        loop {
            let event = event::read()?;
            if let Event::Key(key) = event {
                match Self::handle_key(key, &mut input) {
                    EditorAction::Continue => self.redraw(&mut stdout, &input)?,
                    EditorAction::Submit => {
                        disable_raw_mode()?;
                        writeln!(stdout)?;
                        return Ok(Some(input.as_str().to_owned()));
                    }
                    EditorAction::Cancel => {
                        disable_raw_mode()?;
                        writeln!(stdout)?;
                        return Ok(None);
                    }
                }
            }
        }
    }

    fn read_line_fallback(&self) -> io::Result<Option<String>> {
        let mut stdout = io::stdout();
        write!(stdout, "{}", self.prompt)?;
        stdout.flush()?;

        let mut buffer = String::new();
        let bytes_read = io::stdin().read_line(&mut buffer)?;
        if bytes_read == 0 {
            return Ok(None);
        }

        while matches!(buffer.chars().last(), Some('\n' | '\r')) {
            buffer.pop();
        }
        Ok(Some(buffer))
    }

    fn handle_key(key: KeyEvent, input: &mut InputBuffer) -> EditorAction {
        match key {
            KeyEvent {
                code: KeyCode::Char('c'),
                modifiers,
                ..
            } if modifiers.contains(KeyModifiers::CONTROL) => EditorAction::Cancel,
            KeyEvent {
                code: KeyCode::Char('j'),
                modifiers,
                ..
            } if modifiers.contains(KeyModifiers::CONTROL) => {
                input.insert_newline();
                EditorAction::Continue
            }
            KeyEvent {
                code: KeyCode::Enter,
                modifiers,
                ..
            } if modifiers.contains(KeyModifiers::SHIFT) => {
                input.insert_newline();
                EditorAction::Continue
            }
            KeyEvent {
                code: KeyCode::Enter,
                ..
            } => EditorAction::Submit,
            KeyEvent {
                code: KeyCode::Backspace,
                ..
            } => {
                input.backspace();
                EditorAction::Continue
            }
            KeyEvent {
                code: KeyCode::Left,
                ..
            } => {
                input.move_left();
                EditorAction::Continue
            }
            KeyEvent {
                code: KeyCode::Right,
                ..
            } => {
                input.move_right();
                EditorAction::Continue
            }
            KeyEvent {
                code: KeyCode::Home,
                ..
            } => {
                input.move_home();
                EditorAction::Continue
            }
            KeyEvent {
                code: KeyCode::End, ..
            } => {
                input.move_end();
                EditorAction::Continue
            }
            KeyEvent {
                code: KeyCode::Esc, ..
            } => {
                input.clear();
                EditorAction::Cancel
            }
            KeyEvent {
                code: KeyCode::Char(ch),
                modifiers,
                ..
            } if modifiers.is_empty() || modifiers == KeyModifiers::SHIFT => {
                input.insert(ch);
                EditorAction::Continue
            }
            _ => EditorAction::Continue,
        }
    }

    fn redraw(&self, out: &mut impl Write, input: &InputBuffer) -> io::Result<()> {
        let display = input.as_str().replace('\n', "\\n\n> ");
        queue!(
            out,
            MoveToColumn(0),
            Clear(ClearType::CurrentLine),
            Print(&self.prompt),
            Print(display),
        )?;
        out.flush()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum EditorAction {
    Continue,
    Submit,
    Cancel,
}

#[cfg(test)]
mod tests {
    use super::InputBuffer;

    #[test]
    fn supports_basic_line_editing() {
        let mut input = InputBuffer::new();
        input.insert('h');
        input.insert('i');
        input.move_end();
        input.insert_newline();
        input.insert('x');

        assert_eq!(input.as_str(), "hi\nx");
        assert_eq!(input.cursor(), 4);

        input.move_left();
        input.backspace();
        assert_eq!(input.as_str(), "hix");
        assert_eq!(input.cursor(), 2);
    }
}
