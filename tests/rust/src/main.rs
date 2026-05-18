fn main() {
    let arg = std::env::args().nth(1).unwrap_or_default();
    match arg.as_str() {
        "--version" => println!("nix-bundle-app-rust-demo 0.1.0"),
        "--bundle-id" => println!("nix-bundle-app/e2e"),
        _ => println!("hello from nix-bundle-app rust demo"),
    }
}
