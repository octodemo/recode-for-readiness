//! Command-line entry point.
//!
//! Reads hex-encoded telemetry records on standard input and writes the pass
//! summary to standard output, exactly as the legacy binary does:
//!
//! ```text
//! cargo run --quiet < ../legacy/tests/golden/pass01.tlm
//! ```

use std::io::{Read, Write};

use geosat_modern::pipeline::process;

fn main() -> std::process::ExitCode {
    let mut buffer = Vec::new();
    if let Err(err) = std::io::stdin().read_to_end(&mut buffer) {
        eprintln!("geosat_modern: cannot read stdin: {}", err);
        return std::process::ExitCode::from(1);
    }

    let text = String::from_utf8_lossy(&buffer);

    match process(text.lines()) {
        Ok(result) => {
            let mut out = result.lines.join("\n");
            out.push('\n');
            let stdout = std::io::stdout();
            let mut handle = stdout.lock();
            if let Err(err) = handle.write_all(out.as_bytes()) {
                eprintln!("geosat_modern: cannot write stdout: {}", err);
                return std::process::ExitCode::from(1);
            }
            std::process::ExitCode::SUCCESS
        }
        Err(err) => {
            eprintln!("geosat_modern: {}", err);
            std::process::ExitCode::from(1)
        }
    }
}
