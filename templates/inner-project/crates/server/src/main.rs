use app_core::status_banner;

fn main() {
    println!("{}", status_banner("rust-ts-harness"));
}

#[cfg(test)]
mod tests {
    use super::status_banner;

    #[test]
    fn server_uses_core_banner() {
        assert!(status_banner("test").ends_with("core ready"));
    }
}
