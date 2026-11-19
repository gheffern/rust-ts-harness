/// Returns a canonical status banner for the core engine.
#[must_use]
pub fn status_banner(project_name: &str) -> String {
    format!("{project_name}: core ready")
}

#[cfg(test)]
mod tests {
    use super::status_banner;

    #[test]
    fn status_banner_includes_project_name() {
        assert_eq!(status_banner("demo"), "demo: core ready");
    }
}
