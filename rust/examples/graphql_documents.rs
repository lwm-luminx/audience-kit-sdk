//! Writes every GraphQL document the typed calls can send, built for an audience with every module, to a directory
//! as `<OperationName>.graphql`, so the repository's schema check (scripts/graphql/check.mjs) can validate them:
//!
//! ```sh
//! cargo run --example graphql_documents -- target/graphql
//! ```

use std::{env, fs, path::PathBuf, process};

fn main() {
    let Some(directory) = env::args().nth(1).map(PathBuf::from) else {
        eprintln!("usage: cargo run --example graphql_documents -- <directory>");
        process::exit(2);
    };
    fs::create_dir_all(&directory).expect("create the directory");
    let documents = audiencekit::operations::documents();
    for (name, text) in &documents {
        fs::write(directory.join(format!("{name}.graphql")), format!("{text}\n")).expect("write a document");
    }
    println!("Wrote {} documents to {}.", documents.len(), directory.display());
}
