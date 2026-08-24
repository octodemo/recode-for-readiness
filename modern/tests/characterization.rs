//! Characterization tests: modern port versus the compiled legacy binary.
//!
//! These are not unit tests. They assert one thing only -- that for every
//! golden telemetry vector, the modernized pipeline emits output that is
//! byte-for-byte identical to what the 1987 FORTRAN deck emits on the same
//! input.
//!
//! That is the mission-assurance property. The archive loader parses this
//! output by fixed column position, so "equivalent" is not good enough; it has
//! to be identical.
//!
//! The legacy binary is built on demand. If gfortran is unavailable the parity
//! tests fail loudly rather than silently passing -- a characterization test
//! that cannot execute the reference implementation proves nothing, and a
//! quietly skipped test is worse than a missing one because it reports green.
//!
//! Run:  cargo test

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const VECTORS: [&str; 4] = ["pass01", "pass02", "pass03", "edge01"];

fn repo() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("modern/ must have a parent")
        .to_path_buf()
}

fn legacy_dir() -> PathBuf {
    repo().join("legacy")
}

fn legacy_bin() -> PathBuf {
    legacy_dir().join("build").join("geosat")
}

fn golden(vector: &str) -> PathBuf {
    legacy_dir()
        .join("tests")
        .join("golden")
        .join(format!("{}.tlm", vector))
}

/// Build the reference implementation. Panics with an actionable message if
/// the toolchain is missing, rather than skipping.
fn build_legacy() {
    let gfortran = Command::new("sh")
        .arg("-c")
        .arg("command -v gfortran")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false);

    assert!(
        gfortran,
        "gfortran is not installed, so the reference implementation cannot be \
         built and parity cannot be proven. Install it (brew install gcc) and \
         re-run; do not treat this as a pass."
    );

    let status = Command::new("make")
        .arg("--silent")
        .current_dir(legacy_dir())
        .status()
        .expect("failed to invoke make");

    assert!(status.success(), "legacy build failed");
    assert!(
        legacy_bin().exists(),
        "legacy build reported success but produced no binary"
    );
}

fn run_with_stdin(program: &Path, vector: &str) -> String {
    let input = std::fs::File::open(golden(vector))
        .unwrap_or_else(|e| panic!("cannot open vector {}: {}", vector, e));

    let output = Command::new(program)
        .stdin(Stdio::from(input))
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .unwrap_or_else(|e| panic!("cannot run {}: {}", program.display(), e));

    assert!(
        output.status.success(),
        "{} failed on {}: {}",
        program.display(),
        vector,
        String::from_utf8_lossy(&output.stderr)
    );

    String::from_utf8_lossy(&output.stdout).into_owned()
}

fn run_legacy(vector: &str) -> String {
    run_with_stdin(&legacy_bin(), vector)
}

fn run_modern(vector: &str) -> String {
    run_with_stdin(Path::new(env!("CARGO_BIN_EXE_geosat_modern")), vector)
}

/// Report the first few diverging lines rather than dumping two whole passes.
fn describe_divergence(vector: &str, expected: &str, actual: &str) -> String {
    let exp: Vec<&str> = expected.lines().collect();
    let act: Vec<&str> = actual.lines().collect();
    let mut detail = Vec::new();

    for index in 0..exp.len().max(act.len()) {
        let left = exp.get(index).copied().unwrap_or("<eof>");
        let right = act.get(index).copied().unwrap_or("<eof>");
        if left != right {
            detail.push(format!(
                "line {}\n  legacy: {:?}\n  modern: {:?}",
                index + 1,
                left,
                right
            ));
        }
        if detail.len() >= 5 {
            break;
        }
    }

    format!(
        "output diverged from the legacy binary on {}\n{}",
        vector,
        detail.join("\n")
    )
}

#[test]
fn parity_with_legacy_binary() {
    build_legacy();

    for vector in VECTORS {
        let expected = run_legacy(vector);
        let actual = run_modern(vector);
        assert!(
            expected == actual,
            "{}",
            describe_divergence(vector, &expected, &actual)
        );
    }
}

#[test]
fn expected_files_still_match_the_binary() {
    build_legacy();

    for vector in VECTORS {
        let recorded = std::fs::read_to_string(
            legacy_dir()
                .join("tests")
                .join("expected")
                .join(format!("{}.out", vector)),
        )
        .unwrap_or_else(|e| panic!("cannot read expected output for {}: {}", vector, e));

        assert_eq!(
            recorded,
            run_legacy(vector),
            "checked-in golden output for {} is stale",
            vector
        );
    }
}
