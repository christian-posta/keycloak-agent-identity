#!/usr/bin/env python3
"""
Boot Keycloak: Complete Keycloak Setup and Configuration

This script combines Docker management and Keycloak configuration into a single
streamlined process. It will:
1. Start Keycloak using Docker Compose
2. Wait for Keycloak to be ready
3. Configure Keycloak using setup_keycloak.py
4. Verify the setup was successful

Usage:
    python boot_keycloak.py [--config CONFIG_FILE] [--url KEYCLOAK_URL] [--summary] [--verbose]
"""

import subprocess
import sys
import time
import requests
import json
import os
import argparse
from pathlib import Path
from typing import Dict, Any, Optional, List

# Configuration
DEFAULT_KEYCLOAK_URL = "http://localhost:8080"
DEFAULT_CONFIG_FILE = "config.json"
DEFAULT_ADMIN_USERNAME = "admin"
DEFAULT_ADMIN_PASSWORD = "admin"

class Colors:
    """ANSI color codes for terminal output."""
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    PURPLE = '\033[0;35m'
    CYAN = '\033[0;36m'
    WHITE = '\033[1;37m'
    NC = '\033[0m'  # No Color

def log(message: str, level: str = "INFO", verbose: bool = False):
    """Log messages with color coding."""
    colors = {
        'INFO': f'{Colors.BLUE}ℹ️{Colors.NC}',
        'SUCCESS': f'{Colors.GREEN}✅{Colors.NC}',
        'WARNING': f'{Colors.YELLOW}⚠️{Colors.NC}',
        'ERROR': f'{Colors.RED}❌{Colors.NC}',
        'VERBOSE': f'{Colors.CYAN}🔍{Colors.NC}'
    }
    
    if level == "VERBOSE" and not verbose:
        return
    
    color = colors.get(level, colors['INFO'])
    print(f"{color} {message}")

def run_command(command: str, cwd: Optional[Path] = None, check: bool = True, verbose: bool = False) -> subprocess.CompletedProcess:
    """Run a shell command and return the result."""
    log(f"Running: {command}", verbose=verbose)
    try:
        result = subprocess.run(
            command,
            shell=True,
            cwd=cwd,
            capture_output=True,
            text=True,
            check=check
        )
        if result.stdout and verbose:
            log(f"Output: {result.stdout.strip()}", "VERBOSE")
        if result.stderr and verbose:
            log(f"Stderr: {result.stderr.strip()}", "VERBOSE")
        return result
    except subprocess.CalledProcessError as e:
        log(f"Command failed with exit code {e.returncode}", "ERROR")
        if e.stderr:
            log(f"Error: {e.stderr}", "ERROR")
        if check:
            raise
        return e

def check_keycloak_health(keycloak_url: str) -> bool:
    """Check if Keycloak is healthy and responding."""
    try:
        # Try to access the master realm - this is a reliable way to check if Keycloak is running
        response = requests.get(f"{keycloak_url}/realms/master", timeout=10)
        if response.status_code == 200:
            log("Keycloak health check passed", "SUCCESS")
            return True
        else:
            log(f"Keycloak health check failed with status {response.status_code}", "ERROR")
            return False
    except requests.exceptions.RequestException as e:
        log(f"Keycloak health check failed: {e}", "ERROR")
        return False

def wait_for_keycloak(keycloak_url: str, max_attempts: int = 30) -> bool:
    """Wait for Keycloak to become available."""
    log("Waiting for Keycloak to become available...")
    
    for attempt in range(max_attempts):
        if check_keycloak_health(keycloak_url):
            return True
        
        log(f"Attempt {attempt + 1}/{max_attempts} - Keycloak not ready yet...")
        time.sleep(2)
    
    log("Keycloak failed to become available within expected time", "ERROR")
    return False

def manage_docker_compose(verbose: bool = False) -> bool:
    """Manage Docker Compose for Keycloak."""
    # Use the script's directory as the working directory for Docker operations
    keycloak_dir = Path(__file__).parent
    
    # Check if containers are running and stop them
    log("Checking for existing Keycloak containers...")
    result = run_command("docker compose ps", cwd=keycloak_dir, check=False, verbose=verbose)
    
    if "Up" in result.stdout:
        log("Stopping existing Keycloak containers...")
        run_command("docker compose down", cwd=keycloak_dir, verbose=verbose)
        time.sleep(2)  # Give containers time to stop
    
    # Start fresh Keycloak
    log("Starting Keycloak with Docker Compose...")
    result = run_command("docker compose up -d", cwd=keycloak_dir, verbose=verbose)
    
    if result.returncode != 0:
        log("Failed to start Keycloak containers", "ERROR")
        return False
    
    return True

def run_setup_keycloak(config_file: str, keycloak_url: str, summary: bool = False, verbose: bool = False) -> bool:
    """Run setup_keycloak.py script with the specified configuration."""
    try:
        # Build command to run setup_keycloak.py
        script_dir = Path(__file__).parent
        setup_script = script_dir / "setup_keycloak.py"
        
        cmd = [
            sys.executable, str(setup_script),
            "--config", config_file,
            "--url", keycloak_url
        ]
        
        if summary:
            cmd.append("--summary")
        if verbose:
            cmd.append("--verbose")
        
        log(f"Running Keycloak setup: {' '.join(cmd)}")
        
        # Run the setup script
        result = subprocess.run(
            cmd,
            cwd=script_dir,
            check=True,
            capture_output=False,  # Let output stream directly to console
            text=True
        )
        
        log("Keycloak setup completed successfully", "SUCCESS")
        return True
            
    except subprocess.CalledProcessError as e:
        log(f"Keycloak setup failed: {e}", "ERROR")
        return False
    except Exception as e:
        log(f"Error running Keycloak setup: {e}", "ERROR")
        return False

def load_config(config_file: str) -> Dict[str, Any]:
    """Load configuration from JSON file."""
    try:
        # Handle both relative and absolute paths
        config_path = Path(config_file)
        if not config_path.is_absolute():
            # If relative, try to find it relative to the script's directory
            script_dir = Path(__file__).parent
            config_path = script_dir / config_file
            
        with open(config_path, 'r') as f:
            config = json.load(f)
        log(f"Configuration loaded from {config_path}", "SUCCESS")
        return config
    except Exception as e:
        log(f"Failed to load configuration from {config_file}: {e}", "ERROR")
        sys.exit(1)

def main():
    """Main function."""
    parser = argparse.ArgumentParser(description="Boot and configure Keycloak")
    parser.add_argument("--config", default=DEFAULT_CONFIG_FILE, help="Path to config file")
    parser.add_argument("--url", default=DEFAULT_KEYCLOAK_URL, help="Keycloak URL")
    parser.add_argument("--summary", action="store_true", help="Show detailed summary")
    parser.add_argument("--verbose", action="store_true", help="Verbose output")
    
    args = parser.parse_args()
    
    log("=== Boot Keycloak: Complete Setup and Configuration ===", "INFO")
    
    try:
        # Step 1: Load configuration (just to validate and get realm name)
        # If no config file specified, use the default in the keycloak directory
        if args.config == DEFAULT_CONFIG_FILE:
            script_dir = Path(__file__).parent
            config_path = script_dir / DEFAULT_CONFIG_FILE
            args.config = str(config_path)
            
        config = load_config(args.config)
        realm_name = config['realm']['name']
        
        # Step 2: Manage Docker Compose
        if not manage_docker_compose(args.verbose):
            log("Failed to manage Docker Compose", "ERROR")
            sys.exit(1)
        
        # Step 3: Wait for Keycloak to be ready
        if not wait_for_keycloak(args.url):
            log("Keycloak failed to start", "ERROR")
            sys.exit(1)
        
        # Step 4: Run setup_keycloak.py to configure Keycloak
        if not run_setup_keycloak(args.config, args.url, args.summary, args.verbose):
            log("Failed to setup Keycloak configuration", "ERROR")
            sys.exit(1)
        
        log("=== Boot Keycloak completed successfully! ===", "SUCCESS")
        log("Keycloak is ready for MCP integration")
        log(f"Keycloak URL: {args.url}")
        log(f"Realm: {realm_name}")
        
    except Exception as e:
        log(f"Unexpected error: {e}", "ERROR")
        sys.exit(1)

if __name__ == "__main__":
    main()
