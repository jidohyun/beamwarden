use std::collections::BTreeMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PermissionMode {
    Allow,
    Deny,
    Prompt,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PermissionRequest {
    pub tool_name: String,
    pub input: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PermissionPromptDecision {
    Allow,
    Deny { reason: String },
}

pub trait PermissionPrompter {
    fn decide(&mut self, request: &PermissionRequest) -> PermissionPromptDecision;
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PermissionOutcome {
    Allow,
    Deny { reason: String },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PermissionPolicy {
    default_mode: PermissionMode,
    tool_modes: BTreeMap<String, PermissionMode>,
}

impl PermissionPolicy {
    #[must_use]
    pub fn new(default_mode: PermissionMode) -> Self {
        Self {
            default_mode,
            tool_modes: BTreeMap::new(),
        }
    }

    #[must_use]
    pub fn with_tool_mode(mut self, tool_name: impl Into<String>, mode: PermissionMode) -> Self {
        self.tool_modes.insert(tool_name.into(), mode);
        self
    }

    #[must_use]
    pub fn mode_for(&self, tool_name: &str) -> PermissionMode {
        self.tool_modes
            .get(tool_name)
            .copied()
            .unwrap_or(self.default_mode)
    }

    #[must_use]
    pub fn authorize(
        &self,
        tool_name: &str,
        input: &str,
        mut prompter: Option<&mut dyn PermissionPrompter>,
    ) -> PermissionOutcome {
        match self.mode_for(tool_name) {
            PermissionMode::Allow => PermissionOutcome::Allow,
            PermissionMode::Deny => PermissionOutcome::Deny {
                reason: format!("tool '{tool_name}' denied by permission policy"),
            },
            PermissionMode::Prompt => match prompter.as_mut() {
                Some(prompter) => match prompter.decide(&PermissionRequest {
                    tool_name: tool_name.to_string(),
                    input: input.to_string(),
                }) {
                    PermissionPromptDecision::Allow => PermissionOutcome::Allow,
                    PermissionPromptDecision::Deny { reason } => PermissionOutcome::Deny { reason },
                },
                None => PermissionOutcome::Deny {
                    reason: format!("tool '{tool_name}' requires interactive approval"),
                },
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        PermissionMode, PermissionOutcome, PermissionPolicy, PermissionPromptDecision,
        PermissionPrompter, PermissionRequest,
    };

    struct AllowPrompter;

    impl PermissionPrompter for AllowPrompter {
        fn decide(&mut self, request: &PermissionRequest) -> PermissionPromptDecision {
            assert_eq!(request.tool_name, "bash");
            PermissionPromptDecision::Allow
        }
    }

    #[test]
    fn uses_tool_specific_overrides() {
        let policy = PermissionPolicy::new(PermissionMode::Deny)
            .with_tool_mode("bash", PermissionMode::Prompt);

        let outcome = policy.authorize("bash", "echo hi", Some(&mut AllowPrompter));
        assert_eq!(outcome, PermissionOutcome::Allow);
        assert!(matches!(
            policy.authorize("edit", "x", None),
            PermissionOutcome::Deny { .. }
        ));
    }
}
