use std::fmt::Write as FmtWrite;
use std::io::{self, Write};
use std::thread;
use std::time::Duration;

use crossterm::cursor::{MoveToColumn, RestorePosition, SavePosition};
use crossterm::style::{Color, Print, ResetColor, SetForegroundColor, Stylize};
use crossterm::terminal::{Clear, ClearType};
use crossterm::{execute, queue};
use pulldown_cmark::{CodeBlockKind, Event, Options, Parser, Tag, TagEnd};
use syntect::easy::HighlightLines;
use syntect::highlighting::{Theme, ThemeSet};
use syntect::parsing::SyntaxSet;
use syntect::util::{as_24_bit_terminal_escaped, LinesWithEndings};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ColorTheme {
    heading: Color,
    emphasis: Color,
    strong: Color,
    inline_code: Color,
    link: Color,
    quote: Color,
    spinner_active: Color,
    spinner_done: Color,
    spinner_failed: Color,
}

impl Default for ColorTheme {
    fn default() -> Self {
        Self {
            heading: Color::Cyan,
            emphasis: Color::Magenta,
            strong: Color::Yellow,
            inline_code: Color::Green,
            link: Color::Blue,
            quote: Color::DarkGrey,
            spinner_active: Color::Blue,
            spinner_done: Color::Green,
            spinner_failed: Color::Red,
        }
    }
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct Spinner {
    frame_index: usize,
}

impl Spinner {
    const FRAMES: [&str; 10] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    pub fn tick(
        &mut self,
        label: &str,
        theme: &ColorTheme,
        out: &mut impl Write,
    ) -> io::Result<()> {
        let frame = Self::FRAMES[self.frame_index % Self::FRAMES.len()];
        self.frame_index += 1;
        queue!(
            out,
            SavePosition,
            MoveToColumn(0),
            Clear(ClearType::CurrentLine),
            SetForegroundColor(theme.spinner_active),
            Print(format!("{frame} {label}")),
            ResetColor,
            RestorePosition
        )?;
        out.flush()
    }

    pub fn finish(
        &mut self,
        label: &str,
        theme: &ColorTheme,
        out: &mut impl Write,
    ) -> io::Result<()> {
        self.frame_index = 0;
        execute!(
            out,
            MoveToColumn(0),
            Clear(ClearType::CurrentLine),
            SetForegroundColor(theme.spinner_done),
            Print(format!("✔ {label}\n")),
            ResetColor
        )?;
        out.flush()
    }

    pub fn fail(
        &mut self,
        label: &str,
        theme: &ColorTheme,
        out: &mut impl Write,
    ) -> io::Result<()> {
        self.frame_index = 0;
        execute!(
            out,
            MoveToColumn(0),
            Clear(ClearType::CurrentLine),
            SetForegroundColor(theme.spinner_failed),
            Print(format!("✘ {label}\n")),
            ResetColor
        )?;
        out.flush()
    }
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
struct RenderState {
    emphasis: usize,
    strong: usize,
    quote: usize,
    list: usize,
}

impl RenderState {
    fn style_text(&self, text: &str, theme: &ColorTheme) -> String {
        if self.strong > 0 {
            format!("{}", text.bold().with(theme.strong))
        } else if self.emphasis > 0 {
            format!("{}", text.italic().with(theme.emphasis))
        } else if self.quote > 0 {
            format!("{}", text.with(theme.quote))
        } else {
            text.to_string()
        }
    }
}

#[derive(Debug)]
pub struct TerminalRenderer {
    syntax_set: SyntaxSet,
    syntax_theme: Theme,
    color_theme: ColorTheme,
}

impl Default for TerminalRenderer {
    fn default() -> Self {
        let syntax_set = SyntaxSet::load_defaults_newlines();
        let syntax_theme = ThemeSet::load_defaults()
            .themes
            .remove("base16-ocean.dark")
            .unwrap_or_default();
        Self {
            syntax_set,
            syntax_theme,
            color_theme: ColorTheme::default(),
        }
    }
}

impl TerminalRenderer {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    #[must_use]
    pub fn color_theme(&self) -> &ColorTheme {
        &self.color_theme
    }

    #[must_use]
    pub fn render_markdown(&self, markdown: &str) -> String {
        let mut output = String::new();
        let mut state = RenderState::default();
        let mut code_language = String::new();
        let mut code_buffer = String::new();
        let mut in_code_block = false;

        for event in Parser::new_ext(markdown, Options::all()) {
            self.render_event(
                event,
                &mut state,
                &mut output,
                &mut code_buffer,
                &mut code_language,
                &mut in_code_block,
            );
        }

        output.trim_end().to_string()
    }

    fn render_event(
        &self,
        event: Event<'_>,
        state: &mut RenderState,
        output: &mut String,
        code_buffer: &mut String,
        code_language: &mut String,
        in_code_block: &mut bool,
    ) {
        match event {
            Event::Start(Tag::Heading { level, .. }) => self.start_heading(level as u8, output),
            Event::End(TagEnd::Heading(..) | TagEnd::Paragraph) => output.push_str("\n\n"),
            Event::Start(Tag::BlockQuote(..)) => self.start_quote(state, output),
            Event::End(TagEnd::BlockQuote(..) | TagEnd::Item)
            | Event::SoftBreak
            | Event::HardBreak => output.push('\n'),
            Event::Start(Tag::List(_)) => state.list += 1,
            Event::End(TagEnd::List(..)) => {
                state.list = state.list.saturating_sub(1);
                output.push('\n');
            }
            Event::Start(Tag::Item) => Self::start_item(state, output),
            Event::Start(Tag::CodeBlock(kind)) => {
                *in_code_block = true;
                *code_language = match kind {
                    CodeBlockKind::Indented => String::from("text"),
                    CodeBlockKind::Fenced(lang) => lang.to_string(),
                };
                code_buffer.clear();
                self.start_code_block(code_language, output);
            }
            Event::End(TagEnd::CodeBlock) => {
                self.finish_code_block(code_buffer, code_language, output);
                *in_code_block = false;
                code_language.clear();
                code_buffer.clear();
            }
            Event::Start(Tag::Emphasis) => state.emphasis += 1,
            Event::End(TagEnd::Emphasis) => state.emphasis = state.emphasis.saturating_sub(1),
            Event::Start(Tag::Strong) => state.strong += 1,
            Event::End(TagEnd::Strong) => state.strong = state.strong.saturating_sub(1),
            Event::Code(code) => {
                let _ = write!(
                    output,
                    "{}",
                    format!("`{code}`").with(self.color_theme.inline_code)
                );
            }
            Event::Rule => output.push_str("---\n"),
            Event::Text(text) => {
                self.push_text(text.as_ref(), state, output, code_buffer, *in_code_block);
            }
            Event::Html(html) | Event::InlineHtml(html) => output.push_str(&html),
            Event::FootnoteReference(reference) => {
                let _ = write!(output, "[{reference}]");
            }
            Event::TaskListMarker(done) => output.push_str(if done { "[x] " } else { "[ ] " }),
            Event::InlineMath(math) | Event::DisplayMath(math) => output.push_str(&math),
            Event::Start(Tag::Link { dest_url, .. }) => {
                let _ = write!(
                    output,
                    "{}",
                    format!("[{dest_url}]")
                        .underlined()
                        .with(self.color_theme.link)
                );
            }
            Event::Start(Tag::Image { dest_url, .. }) => {
                let _ = write!(
                    output,
                    "{}",
                    format!("[image:{dest_url}]").with(self.color_theme.link)
                );
            }
            Event::Start(
                Tag::Paragraph
                | Tag::Table(..)
                | Tag::TableHead
                | Tag::TableRow
                | Tag::TableCell
                | Tag::MetadataBlock(..)
                | _,
            )
            | Event::End(
                TagEnd::Link
                | TagEnd::Image
                | TagEnd::Table
                | TagEnd::TableHead
                | TagEnd::TableRow
                | TagEnd::TableCell
                | TagEnd::MetadataBlock(..)
                | _,
            ) => {}
        }
    }

    fn start_heading(&self, level: u8, output: &mut String) {
        output.push('\n');
        let prefix = match level {
            1 => "# ",
            2 => "## ",
            3 => "### ",
            _ => "#### ",
        };
        let _ = write!(output, "{}", prefix.bold().with(self.color_theme.heading));
    }

    fn start_quote(&self, state: &mut RenderState, output: &mut String) {
        state.quote += 1;
        let _ = write!(output, "{}", "│ ".with(self.color_theme.quote));
    }

    fn start_item(state: &RenderState, output: &mut String) {
        output.push_str(&"  ".repeat(state.list.saturating_sub(1)));
        output.push_str("• ");
    }

    fn start_code_block(&self, code_language: &str, output: &mut String) {
        if !code_language.is_empty() {
            let _ = writeln!(
                output,
                "{}",
                format!("╭─ {code_language}").with(self.color_theme.heading)
            );
        }
    }

    fn finish_code_block(&self, code_buffer: &str, code_language: &str, output: &mut String) {
        output.push_str(&self.highlight_code(code_buffer, code_language));
        if !code_language.is_empty() {
            let _ = write!(output, "{}", "╰─".with(self.color_theme.heading));
        }
        output.push_str("\n\n");
    }

    fn push_text(
        &self,
        text: &str,
        state: &RenderState,
        output: &mut String,
        code_buffer: &mut String,
        in_code_block: bool,
    ) {
        if in_code_block {
            code_buffer.push_str(text);
        } else {
            output.push_str(&state.style_text(text, &self.color_theme));
        }
    }

    #[must_use]
    pub fn highlight_code(&self, code: &str, language: &str) -> String {
        let syntax = self
            .syntax_set
            .find_syntax_by_token(language)
            .unwrap_or_else(|| self.syntax_set.find_syntax_plain_text());
        let mut syntax_highlighter = HighlightLines::new(syntax, &self.syntax_theme);
        let mut colored_output = String::new();

        for line in LinesWithEndings::from(code) {
            match syntax_highlighter.highlight_line(line, &self.syntax_set) {
                Ok(ranges) => {
                    colored_output.push_str(&as_24_bit_terminal_escaped(&ranges[..], false));
                }
                Err(_) => colored_output.push_str(line),
            }
        }

        colored_output
    }

    pub fn stream_markdown(&self, markdown: &str, out: &mut impl Write) -> io::Result<()> {
        let rendered_markdown = self.render_markdown(markdown);
        for chunk in rendered_markdown.split_inclusive(char::is_whitespace) {
            write!(out, "{chunk}")?;
            out.flush()?;
            thread::sleep(Duration::from_millis(8));
        }
        writeln!(out)
    }
}

#[cfg(test)]
mod tests {
    use super::{Spinner, TerminalRenderer};

    fn strip_ansi(input: &str) -> String {
        let mut output = String::new();
        let mut chars = input.chars().peekable();

        while let Some(ch) = chars.next() {
            if ch == '\u{1b}' {
                if chars.peek() == Some(&'[') {
                    chars.next();
                    for next in chars.by_ref() {
                        if next.is_ascii_alphabetic() {
                            break;
                        }
                    }
                }
            } else {
                output.push(ch);
            }
        }

        output
    }

    #[test]
    fn renders_markdown_with_styling_and_lists() {
        let terminal_renderer = TerminalRenderer::new();
        let markdown_output = terminal_renderer
            .render_markdown("# Heading\n\nThis is **bold** and *italic*.\n\n- item\n\n`code`");

        assert!(markdown_output.contains("Heading"));
        assert!(markdown_output.contains("• item"));
        assert!(markdown_output.contains("code"));
        assert!(markdown_output.contains('\u{1b}'));
    }

    #[test]
    fn highlights_fenced_code_blocks() {
        let terminal_renderer = TerminalRenderer::new();
        let markdown_output =
            terminal_renderer.render_markdown("```rust\nfn hi() { println!(\"hi\"); }\n```");
        let plain_text = strip_ansi(&markdown_output);

        assert!(plain_text.contains("╭─ rust"));
        assert!(plain_text.contains("fn hi"));
        assert!(markdown_output.contains('\u{1b}'));
    }

    #[test]
    fn spinner_advances_frames() {
        let terminal_renderer = TerminalRenderer::new();
        let mut spinner = Spinner::new();
        let mut out = Vec::new();
        spinner
            .tick("Working", terminal_renderer.color_theme(), &mut out)
            .expect("tick succeeds");
        spinner
            .tick("Working", terminal_renderer.color_theme(), &mut out)
            .expect("tick succeeds");

        let output = String::from_utf8_lossy(&out);
        assert!(output.contains("Working"));
    }
}
