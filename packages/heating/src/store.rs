use std::fs::{self, File};
use std::io::{ErrorKind, Write};
use std::path::PathBuf;

use anyhow::Context;
use log::{error, warn};

use crate::core::Persisted;

pub struct Store {
    path: PathBuf,
}

impl Store {
    pub fn new(path: PathBuf) -> Self {
        Self { path }
    }

    /// Falls back to the defaults on any problem rather than refusing to
    /// start: the file only holds settings made in the web UI, and heating
    /// with the defaults beats not heating.
    pub fn load(&self) -> Persisted {
        let text = match fs::read_to_string(&self.path) {
            Ok(text) => text,
            Err(err) if err.kind() == ErrorKind::NotFound => {
                warn!("no saved state at {}, using defaults", self.path.display());
                return Persisted::default();
            }
            Err(err) => {
                error!("reading {}: {err}, using defaults", self.path.display());
                return Persisted::default();
            }
        };
        match serde_json::from_str(&text) {
            Ok(persisted) => persisted,
            Err(err) => {
                error!("parsing {}: {err}, using defaults", self.path.display());
                Persisted::default()
            }
        }
    }

    pub fn save(&self, persisted: &Persisted) -> anyhow::Result<()> {
        let tmp_path = self.path.with_extension("tmp");
        let text = serde_json::to_string_pretty(persisted).context("serialising state")?;
        let mut file =
            File::create(&tmp_path).with_context(|| format!("creating {}", tmp_path.display()))?;
        file.write_all(text.as_bytes())
            .and_then(|()| file.sync_all())
            .with_context(|| format!("writing {}", tmp_path.display()))?;
        fs::rename(&tmp_path, &self.path).with_context(|| {
            format!("renaming {} to {}", tmp_path.display(), self.path.display())
        })?;
        Ok(())
    }
}

#[cfg(test)]
pub mod tests {
    use std::path::{Path, PathBuf};
    use std::sync::atomic::{AtomicUsize, Ordering};

    use super::*;
    use crate::config::Params;

    /// A fresh directory under the system temp dir, removed on drop.
    pub struct TempDir(PathBuf);

    impl TempDir {
        pub fn new() -> Self {
            static COUNT: AtomicUsize = AtomicUsize::new(0);
            let path = std::env::temp_dir().join(format!(
                "heating-test-{}-{}",
                std::process::id(),
                COUNT.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir_all(&path).unwrap();
            Self(path)
        }

        pub fn path(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn round_trips() {
        let dir = TempDir::new();
        let store = Store::new(dir.path().join("state.json"));
        let persisted = Persisted {
            targets: [("bedroom".to_owned(), 19.5)].into_iter().collect(),
            params: Some(Params::default()),
        };
        store.save(&persisted).unwrap();
        assert_eq!(store.load(), persisted);
        assert!(!dir.path().join("state.tmp").exists());
    }

    #[test]
    fn missing_or_corrupt_files_give_defaults() {
        let dir = TempDir::new();
        let path = dir.path().join("state.json");
        let store = Store::new(path.clone());
        assert_eq!(store.load(), Persisted::default());
        fs::write(&path, "{not json").unwrap();
        assert_eq!(store.load(), Persisted::default());
        fs::write(&path, r#"{"targets": {"bedroom": "warm"}}"#).unwrap();
        assert_eq!(store.load(), Persisted::default());
    }

    #[test]
    fn saving_into_a_missing_directory_fails() {
        let dir = TempDir::new();
        let store = Store::new(dir.path().join("nope").join("state.json"));
        assert!(store.save(&Persisted::default()).is_err());
    }
}
