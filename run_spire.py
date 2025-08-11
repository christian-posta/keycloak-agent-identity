#!/usr/bin/env python3
"""
Wrapper script to run spire-up.sh or spire-down.sh from the spire directory.
This allows uv run spire [--down] to work from the project root.
"""

import os
import sys
import subprocess
import argparse
from pathlib import Path

def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser(description="Manage SPIRE stack")
    parser.add_argument("--down", action="store_true", help="Shutdown SPIRE stack")
    args = parser.parse_args()
    
    # Get the project root directory (where this script is located)
    project_root = Path(__file__).parent
    spire_dir = project_root / "spire"
    
    # Check if spire directory exists
    if not spire_dir.exists():
        print(f"Error: spire directory not found at {spire_dir}")
        sys.exit(1)
    
    # Determine which script to run
    if args.down:
        script_name = "spire-down.sh"
        action_verb = "Shutting down"
        success_msg = "✅ SPIRE stack shutdown completed!"
    else:
        script_name = "spire-up.sh"
        action_verb = "Starting"
        success_msg = "✅ SPIRE stack started successfully!"
    
    spire_script = spire_dir / script_name
    if not spire_script.exists():
        print(f"Error: {script_name} not found at {spire_script}")
        sys.exit(1)
    
    # Change to the spire directory
    original_cwd = os.getcwd()
    os.chdir(spire_dir)
    
    try:
        # Make sure the script is executable
        os.chmod(spire_script, 0o755)
        
        # Run the appropriate script
        print(f"🚀 {action_verb} SPIRE stack...")
        result = subprocess.run(
            [f"./{script_name}"],
            cwd=spire_dir,
            check=True
        )
        
        if result.returncode == 0:
            print(success_msg)
        else:
            print(f"❌ SPIRE script failed with exit code {result.returncode}")
            sys.exit(result.returncode)
            
    except subprocess.CalledProcessError as e:
        print(f"❌ Error running SPIRE script: {e}")
        sys.exit(e.returncode)
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        sys.exit(1)
    finally:
        # Restore original working directory
        os.chdir(original_cwd)

if __name__ == "__main__":
    main()
