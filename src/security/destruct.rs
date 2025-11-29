/// Secure binary deletion on unauthorized access
use std::fs;
use std::io::{Seek, SeekFrom, Write};
use std::process::exit;

/// Securely delete the binary on unauthorized access
/// 
/// Process:
/// 1. Overwrite binary with random data (3 passes)
/// 2. Delete the file
/// 3. Delete the config file
/// 4. Exit with error code
#[cfg(unix)]
pub fn secure_delete_self() -> ! {
    eprintln!("🔥 Unauthorized access detected. Initiating secure deletion...");

    let exe_path = match std::env::current_exe() {
        Ok(path) => path,
        Err(e) => {
            eprintln!("Failed to get executable path: {}", e);
            exit(1);
        }
    };

    // Get file size
    let file_size = match fs::metadata(&exe_path) {
        Ok(meta) => meta.len() as usize,
        Err(e) => {
            eprintln!("Failed to get file metadata: {}", e);
            exit(1);
        }
    };

    // Overwrite with random data (3 passes)
    if let Ok(mut file) = fs::OpenOptions::new().write(true).open(&exe_path) {
        for pass in 1..=3 {
            eprintln!("  Pass {}/3: Overwriting with random data...", pass);
            
            // Generate random data
            let random_data: Vec<u8> = (0..file_size)
                .map(|_| rand::random::<u8>())
                .collect();

            // Write random data
            if let Err(e) = file.seek(SeekFrom::Start(0)) {
                eprintln!("Failed to seek: {}", e);
                continue;
            }

            if let Err(e) = file.write_all(&random_data) {
                eprintln!("Failed to write random data: {}", e);
                continue;
            }

            if let Err(e) = file.flush() {
                eprintln!("Failed to flush: {}", e);
            }
        }
    }

    // Delete the binary file
    match fs::remove_file(&exe_path) {
        Ok(_) => eprintln!("✅ Binary securely deleted"),
        Err(e) => eprintln!("Failed to delete binary: {}", e),
    }

    // Delete the config file
    let config_path = format!("{}.config", exe_path.display());
    match fs::remove_file(&config_path) {
        Ok(_) => eprintln!("✅ Config file deleted"),
        Err(e) => eprintln!("Failed to delete config: {}", e),
    }

    eprintln!("❌ License verification failed. Binary and config have been removed.");
    exit(1);
}

#[cfg(windows)]
pub fn secure_delete_self() -> ! {
    eprintln!("🔥 Unauthorized access detected. Initiating secure deletion...");

    let exe_path = match std::env::current_exe() {
        Ok(path) => path,
        Err(e) => {
            eprintln!("Failed to get executable path: {}", e);
            exit(1);
        }
    };

    // On Windows, we cannot overwrite/delete a running executable.
    // We create a temporary batch script to delete the file after we exit.
    
    let batch_path = exe_path.with_extension("bat");
    let exe_name = exe_path.file_name().unwrap_or_default().to_string_lossy();
    
    eprintln!("  Creating self-deletion script: {}", batch_path.display());

    // Batch script that loops until the file is deleted (when we exit)
    // Then deletes itself
    let batch_content = format!(
        "@echo off\r\n\
         :loop\r\n\
         del \"{}\" > NUL 2>&1\r\n\
         if exist \"{}\" goto loop\r\n\
         del \"%~f0\" > NUL 2>&1\r\n",
        exe_path.display(),
        exe_path.display()
    );

    if let Ok(mut file) = fs::File::create(&batch_path) {
        if let Err(e) = file.write_all(batch_content.as_bytes()) {
             eprintln!("Failed to write batch file: {}", e);
        }
    } else {
        eprintln!("Failed to create batch file");
    }

    // Execute the batch file in background
    let _ = std::process::Command::new("cmd")
        .arg("/C")
        .arg(&batch_path)
        .spawn();
        
    // Also try to delete config file immediately (it's not locked)
    let config_path = format!("{}.config", exe_path.display());
    let _ = fs::remove_file(&config_path);

    eprintln!("❌ License verification failed. Self-destruct sequence initiated.");
    exit(1);
}

/// Secure deletion with custom file path
/// Used for deleting base binary in async mode
pub fn secure_delete_file(file_path: &str) {
    eprintln!("🔥 Securely deleting: {}", file_path);
    
    // Get file size
    let file_size = match fs::metadata(file_path) {
        Ok(meta) => meta.len() as usize,
        Err(e) => {
            eprintln!("Failed to get file metadata: {}", e);
            return;
        }
    };
    
    // Overwrite with random data (3 passes)
    if let Ok(mut file) = fs::OpenOptions::new().write(true).open(file_path) {
        for pass in 1..=3 {
            eprintln!("  Pass {}/3: Overwriting {} with random data...", pass, file_path);
            
            let random_data: Vec<u8> = (0..file_size)
                .map(|_| rand::random::<u8>())
                .collect();
            
            if file.seek(SeekFrom::Start(0)).is_ok() {
                let _ = file.write_all(&random_data);
                let _ = file.flush();
            }
        }
    }
    
    // Delete the file
    match fs::remove_file(file_path) {
        Ok(_) => eprintln!("✅ File deleted: {}", file_path),
        Err(e) => eprintln!("Failed to delete {}: {}", file_path, e),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::NamedTempFile;
    
    #[test]
    fn test_secure_delete_file() {
        // Create a temp file
        let mut temp_file = NamedTempFile::new().unwrap();
        temp_file.write_all(b"test data").unwrap();
        temp_file.flush().unwrap();
        
        let path = temp_file.path().to_string_lossy().to_string();
        
        // Secure delete it
        secure_delete_file(&path);
        
        // Verify it's gone
        assert!(!std::path::Path::new(&path).exists());
    }
}
