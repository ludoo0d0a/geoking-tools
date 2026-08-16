#!/usr/bin/env python3
"""
Roundtrip Translation Comparison Script

This script compares roundtrip translations (translated back to English) 
with the original English strings.xml file to identify differences and 
assess translation quality.
"""

import xml.etree.ElementTree as ET
import os
import sys
from pathlib import Path
from difflib import unified_diff
import argparse
import html
from datetime import datetime

def parse_strings_xml(file_path):
    """Parse strings.xml file and return a dictionary of string entries."""
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        strings = {}
        for string_elem in root.findall('string'):
            name = string_elem.get('name')
            translatable = string_elem.get('translatable', 'true')
            text = string_elem.text or ''
            
            strings[name] = {
                'text': text,
                'translatable': translatable == 'true',
                'raw_xml': ET.tostring(string_elem, encoding='unicode').strip()
            }
        
        return strings
    except ET.ParseError as e:
        print(f"Error parsing {file_path}: {e}")
        return {}
    except FileNotFoundError:
        print(f"File not found: {file_path}")
        return {}

def normalize_text(text, ignore_case=True, min_word_length=4):
    """Normalize text by removing extra whitespace, normalizing spaces, optionally ignoring case, and filtering short words."""
    if not text:
        return ''
    # Replace multiple whitespace with single space, strip leading/trailing
    import re
    normalized = re.sub(r'\s+', ' ', text.strip())
    
    # Convert to lowercase if case should be ignored
    if ignore_case:
        normalized = normalized.lower()
    
    # Filter out words shorter than min_word_length
    if min_word_length > 0:
        words = normalized.split()
        filtered_words = [word for word in words if len(word) >= min_word_length]
        normalized = ' '.join(filtered_words)
    
    return normalized

def compare_strings(original, roundtrip, language):
    """Compare original and roundtrip strings and return differences."""
    differences = []
    
    # Get all string names from both files
    all_names = set(original.keys()) | set(roundtrip.keys())
    
    for name in sorted(all_names):
        orig_entry = original.get(name)
        roundtrip_entry = roundtrip.get(name)
        
        if orig_entry is None:
            differences.append({
                'name': name,
                'type': 'missing_in_original',
                'roundtrip_text': roundtrip_entry['text'] if roundtrip_entry else '',
                'original_text': ''
            })
        elif roundtrip_entry is None:
            differences.append({
                'name': name,
                'type': 'missing_in_roundtrip',
                'original_text': orig_entry['text'],
                'roundtrip_text': ''
            })
        else:
            # Compare text content with whitespace normalization
            orig_text = orig_entry['text']
            roundtrip_text = roundtrip_entry['text']
            
            # Normalize both texts for comparison (ignore case, whitespace, and short words)
            orig_normalized = normalize_text(orig_text, ignore_case=True, min_word_length=4)
            roundtrip_normalized = normalize_text(roundtrip_text, ignore_case=True, min_word_length=4)
            
            if orig_normalized != roundtrip_normalized:
                differences.append({
                    'name': name,
                    'type': 'text_difference',
                    'original_text': orig_text,
                    'roundtrip_text': roundtrip_text,
                    'original_normalized': orig_normalized,
                    'roundtrip_normalized': roundtrip_normalized,
                    'translatable': orig_entry['translatable']
                })
    
    return differences

def print_differences(differences, language, show_all=False, ignore_whitespace=True, ignore_case=True, min_word_length=4):
    """Print formatted differences in compact 3-column format."""
    if not differences:
        print(f"✅ {language}: No differences found!")
        return
    
    # Filter out whitespace/case/short-word-only differences if requested
    if ignore_whitespace or ignore_case or min_word_length > 0:
        meaningful_diffs = []
        for diff in differences:
            if diff['type'] == 'text_difference':
                # Check if the only difference is whitespace/case/short words
                orig_norm = diff.get('original_normalized', normalize_text(diff['original_text'], ignore_case, min_word_length))
                roundtrip_norm = diff.get('roundtrip_normalized', normalize_text(diff['roundtrip_text'], ignore_case, min_word_length))
                if orig_norm != roundtrip_norm:
                    meaningful_diffs.append(diff)
            else:
                meaningful_diffs.append(diff)
        differences = meaningful_diffs
    
    if not differences:
        ignored = []
        if ignore_whitespace:
            ignored.append("whitespace")
        if ignore_case:
            ignored.append("case")
        if min_word_length > 0:
            ignored.append(f"words<{min_word_length}chars")
        print(f"✅ {language}: No meaningful differences found! ({', '.join(ignored)} ignored)")
        return
    
    print(f"\n🔍 {language.upper()} - Found {len(differences)} differences:")
    print("=" * 120)
    
    # Calculate column widths
    max_key_width = max(len(diff['name']) for diff in differences) + 2
    max_text_width = 0
    for diff in differences:
        if diff['type'] == 'text_difference':
            max_text_width = max(max_text_width, len(diff['original_text']), len(diff['roundtrip_text']))
        elif diff['type'] == 'missing_in_original':
            max_text_width = max(max_text_width, len(diff['roundtrip_text']))
        elif diff['type'] == 'missing_in_roundtrip':
            max_text_width = max(max_text_width, len(diff['original_text']))
    
    # Ensure minimum widths
    max_key_width = max(max_key_width, 15)
    max_text_width = max(max_text_width, 20)
    
    # Print header
    print(f"{'KEY':<{max_key_width}} {'ORIGINAL/ROUNDTRIP':<{max_text_width}} {'NORMALIZED':<{max_text_width}}")
    print("-" * (max_key_width + max_text_width * 2 + 4))
    
    for diff in differences:
        if not show_all and diff['type'] == 'text_difference' and not diff['translatable']:
            continue  # Skip non-translatable strings unless show_all is True
        
        key = diff['name']
        
        if diff['type'] == 'text_difference':
            orig_text = diff['original_text']
            roundtrip_text = diff['roundtrip_text']
            orig_norm = diff.get('original_normalized', normalize_text(orig_text, ignore_case, min_word_length))
            roundtrip_norm = diff.get('roundtrip_normalized', normalize_text(roundtrip_text, ignore_case, min_word_length))
            
            # Truncate long texts for display
            orig_display = orig_text if len(orig_text) <= max_text_width else orig_text[:max_text_width-3] + "..."
            roundtrip_display = roundtrip_text if len(roundtrip_text) <= max_text_width else roundtrip_text[:max_text_width-3] + "..."
            orig_norm_display = orig_norm if len(orig_norm) <= max_text_width else orig_norm[:max_text_width-3] + "..."
            roundtrip_norm_display = roundtrip_norm if len(roundtrip_norm) <= max_text_width else roundtrip_norm[:max_text_width-3] + "..."
            
            print(f"{key:<{max_key_width}} {orig_display:<{max_text_width}} {orig_norm_display:<{max_text_width}}")
            print(f"{'':<{max_key_width}} {roundtrip_display:<{max_text_width}} {roundtrip_norm_display:<{max_text_width}}")
        
        elif diff['type'] == 'missing_in_original':
            roundtrip_text = diff['roundtrip_text']
            roundtrip_display = roundtrip_text if len(roundtrip_text) <= max_text_width else roundtrip_text[:max_text_width-3] + "..."
            print(f"{key:<{max_key_width}} {'[MISSING]':<{max_text_width}} {'':<{max_text_width}}")
            print(f"{'':<{max_key_width}} {roundtrip_display:<{max_text_width}} {'':<{max_text_width}}")
        
        elif diff['type'] == 'missing_in_roundtrip':
            orig_text = diff['original_text']
            orig_display = orig_text if len(orig_text) <= max_text_width else orig_text[:max_text_width-3] + "..."
            print(f"{key:<{max_key_width}} {orig_display:<{max_text_width}} {'':<{max_text_width}}")
            print(f"{'':<{max_key_width}} {'[MISSING]':<{max_text_width}} {'':<{max_text_width}}")
        
        print()  # Empty line between entries

def generate_html_report(all_results, original_file, output_file, min_word_length=4):
    """Generate a compact HTML report showing only differences."""
    
    # Filter out languages with no differences and apply word filtering
    languages_with_differences = {}
    for lang, result in all_results.items():
        if result['differences']:
            # Apply word filtering to differences
            filtered_differences = []
            for diff in result['differences']:
                if diff['type'] == 'text_difference':
                    orig_norm = diff.get('original_normalized', normalize_text(diff['original_text'], True, min_word_length))
                    roundtrip_norm = diff.get('roundtrip_normalized', normalize_text(diff['roundtrip_text'], True, min_word_length))
                    if orig_norm != roundtrip_norm:
                        filtered_differences.append(diff)
                else:
                    filtered_differences.append(diff)
            
            if filtered_differences:
                languages_with_differences[lang] = {
                    'differences': filtered_differences,
                    'total_strings': result['total_strings']
                }
    
    if not languages_with_differences:
        # No differences found
        html_content = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Roundtrip Translation Report - No Differences</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
            text-align: center;
        }}
        .container {{
            max-width: 600px;
            margin: 50px auto;
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            padding: 40px;
        }}
        .success {{
            color: #28a745;
            font-size: 4em;
            margin-bottom: 20px;
        }}
        h1 {{
            color: #333;
            margin-bottom: 10px;
        }}
        .subtitle {{
            color: #666;
            margin-bottom: 30px;
        }}
        .info {{
            background: #f8f9fa;
            padding: 15px;
            border-radius: 4px;
            font-size: 0.9em;
            color: #666;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="success">✅</div>
        <h1>Perfect Translation Quality!</h1>
        <p class="subtitle">All roundtrip translations match the original exactly</p>
        <div class="info">
            <strong>Generated:</strong> {datetime.now().strftime('%B %d, %Y at %I:%M %p')}<br>
            <strong>Original file:</strong> {html.escape(original_file)}
        </div>
    </div>
</body>
</html>
"""
    else:
        # Calculate summary statistics
        total_differences = sum(len(result['differences']) for result in languages_with_differences.values())
        
        # Generate compact HTML content
        html_content = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Roundtrip Translation Differences Report</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.4;
            margin: 0;
            padding: 15px;
            background-color: #f8f9fa;
            font-size: 14px;
        }}
        .container {{
            max-width: 1000px;
            margin: 0 auto;
            background: white;
            border-radius: 6px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            overflow: hidden;
        }}
        .header {{
            background: #495057;
            color: white;
            padding: 15px 20px;
            text-align: center;
        }}
        .header h1 {{
            margin: 0;
            font-size: 1.5em;
            font-weight: 500;
        }}
        .header p {{
            margin: 5px 0 0 0;
            opacity: 0.9;
            font-size: 0.9em;
        }}
        .summary {{
            background: #e9ecef;
            padding: 10px 20px;
            border-bottom: 1px solid #dee2e6;
            font-size: 0.9em;
            color: #495057;
        }}
        .language-section {{
            border-bottom: 1px solid #dee2e6;
        }}
        .language-header {{
            background: #f8f9fa;
            padding: 8px 15px;
            border-bottom: 1px solid #dee2e6;
            font-weight: 600;
            color: #495057;
            font-size: 1.1em;
        }}
        .differences-list {{
            margin: 0;
            padding: 0;
        }}
        .difference-item {{
            border-bottom: 1px solid #f1f3f4;
            padding: 12px 15px;
        }}
        .difference-item:last-child {{
            border-bottom: none;
        }}
        .difference-header {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 8px;
        }}
        .string-name {{
            font-weight: 600;
            color: #212529;
            font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
            font-size: 0.9em;
        }}
        .difference-type {{
            padding: 2px 6px;
            border-radius: 3px;
            font-size: 0.75em;
            font-weight: 500;
        }}
        .difference-type.text_difference {{
            background: #cce5ff;
            color: #0066cc;
        }}
        .difference-type.missing_in_original {{
            background: #ffcccb;
            color: #cc0000;
        }}
        .difference-type.missing_in_roundtrip {{
            background: #ffe4b5;
            color: #cc6600;
        }}
        .compact-table {{
            width: 100%;
            border-collapse: collapse;
            margin: 8px 0;
            font-size: 0.9em;
        }}
        .compact-table th {{
            background: #f8f9fa;
            border: 1px solid #dee2e6;
            padding: 8px 12px;
            text-align: left;
            font-weight: 600;
            color: #495057;
            font-size: 0.8em;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }}
        .compact-table td {{
            border: 1px solid #e9ecef;
            padding: 8px 12px;
            vertical-align: top;
        }}
        .compact-table .key-column {{
            background: #f8f9fa;
            font-weight: 600;
            font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
            color: #212529;
            width: 20%;
        }}
        .compact-table .text-column {{
            background: #ffffff;
            font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
            font-size: 0.85em;
            white-space: pre-wrap;
            word-break: break-word;
            color: #212529;
            width: 40%;
        }}
        .compact-table .normalized-column {{
            background: #f0f8ff;
            font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
            font-size: 0.8em;
            color: #1565c0;
            width: 40%;
        }}
        .compact-table .original-row {{
            border-bottom: none;
        }}
        .compact-table .roundtrip-row {{
            border-top: 1px dashed #dee2e6;
        }}
        .normalized-comparison {{
            background: #e3f2fd;
            border: 1px solid #bbdefb;
            border-radius: 3px;
            padding: 6px 8px;
            margin: 6px 0;
            font-size: 0.8em;
        }}
        .normalized-comparison h6 {{
            margin: 0 0 4px 0;
            color: #1976d2;
            font-size: 0.75em;
        }}
        .normalized-text {{
            font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
            color: #1565c0;
        }}
        .footer {{
            background: #f8f9fa;
            padding: 10px 20px;
            text-align: center;
            color: #6c757d;
            font-size: 0.8em;
            border-top: 1px solid #dee2e6;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔄 Translation Differences Report</h1>
            <p>Generated on {datetime.now().strftime('%B %d, %Y at %I:%M %p')}</p>
        </div>
        
        <div class="summary">
            <strong>{len(languages_with_differences)} languages</strong> with differences • 
            <strong>{total_differences} total differences</strong> • 
            Case-insensitive comparison • Words ≥{min_word_length} chars
        </div>
"""

        # Add language sections (only those with differences)
        for lang_key, result in languages_with_differences.items():
            differences = result['differences']
            
            html_content += f"""
        <div class="language-section">
            <div class="language-header">
                {lang_key.upper().replace('-', '/')} ({len(differences)} differences)
            </div>
            <div class="differences-list">
"""
            
            # Generate compact table for all differences
            html_content += """
            <table class="compact-table">
                <thead>
                    <tr>
                        <th>KEY</th>
                        <th>ORIGINAL / ROUNDTRIP</th>
                        <th>NORMALIZED</th>
                    </tr>
                </thead>
                <tbody>
"""
            
            for diff in differences:
                if diff['type'] == 'text_difference':
                    orig_text = html.escape(diff['original_text'])
                    roundtrip_text = html.escape(diff['roundtrip_text'])
                    orig_norm = html.escape(diff.get('original_normalized', ''))
                    roundtrip_norm = html.escape(diff.get('roundtrip_normalized', ''))
                    
                    html_content += f"""
                    <tr class="original-row">
                        <td class="key-column" rowspan="2">{html.escape(diff['name'])}</td>
                        <td class="text-column">{orig_text}</td>
                        <td class="normalized-column">{orig_norm}</td>
                    </tr>
                    <tr class="roundtrip-row">
                        <td class="text-column">{roundtrip_text}</td>
                        <td class="normalized-column">{roundtrip_norm}</td>
                    </tr>
"""
                
                elif diff['type'] == 'missing_in_original':
                    roundtrip_text = html.escape(diff['roundtrip_text'])
                    html_content += f"""
                    <tr class="original-row">
                        <td class="key-column" rowspan="2">{html.escape(diff['name'])}</td>
                        <td class="text-column">[MISSING]</td>
                        <td class="normalized-column"></td>
                    </tr>
                    <tr class="roundtrip-row">
                        <td class="text-column">{roundtrip_text}</td>
                        <td class="normalized-column"></td>
                    </tr>
"""
                
                elif diff['type'] == 'missing_in_roundtrip':
                    orig_text = html.escape(diff['original_text'])
                    html_content += f"""
                    <tr class="original-row">
                        <td class="key-column" rowspan="2">{html.escape(diff['name'])}</td>
                        <td class="text-column">{orig_text}</td>
                        <td class="normalized-column"></td>
                    </tr>
                    <tr class="roundtrip-row">
                        <td class="text-column">[MISSING]</td>
                        <td class="normalized-column"></td>
                    </tr>
"""
            
            html_content += """
                </tbody>
            </table>
"""
            
            html_content += '</div></div>'
    
        # Add footer
        html_content += """
        <div class="footer">
            <p>Generated by Roundtrip Translation Comparison Tool • Case-insensitive comparison</p>
        </div>
    </div>
</body>
</html>
"""
    
    # Write HTML file
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(html_content)
    
    return output_file

def main():
    parser = argparse.ArgumentParser(description='Compare roundtrip translations with original English')
    parser.add_argument('--original', '-o',
                       default='app/src/main/res/values/strings.xml',
                       help='Path to original English strings.xml (used only when --modules is not provided)')
    parser.add_argument('--roundtrip-dir', '-d',
                       default='i18n',
                       help='Base directory containing roundtrip translations')
    parser.add_argument('--modules', '-m', nargs='+',
                       default=['app', 'shared', 'wear'],
                       help='Modules to compare: any of app shared wear (default: all)')
    parser.add_argument('--use-draft', action='store_true',
                       help='Look for files under draft/{module}/{lang}-to-en/strings.xml')
    parser.add_argument('--show-all', '-a', action='store_true',
                       help='Show all differences including non-translatable strings')
    parser.add_argument('--languages', '-l', nargs='+',
                       default=['da', 'de', 'es', 'fr', 'it', 'ja', 'ko', 'nb', 'pl', 'ru', 'sv', 'tr', 'zh'],
                       help='Languages to compare (default: da de es fr it ja ko nb pl ru sv tr zh)')
    parser.add_argument('--include-whitespace', '-w', action='store_true',
                       help='Include whitespace-only differences in comparison')
    parser.add_argument('--include-case', '-c', action='store_true',
                       help='Include case-only differences in comparison')
    parser.add_argument('--min-word-length', type=int, default=4,
                       help='Minimum word length to consider in comparison (default: 4)')
    parser.add_argument('--html', action='store_true',
                       help='Generate HTML report instead of console output')
    parser.add_argument('--output', default='roundtrip_report.html',
                       help='Output file for HTML report (default: roundtrip_report.html)')
    
    args = parser.parse_args()
    
    # Get absolute paths
    script_dir = Path(__file__).parent
    project_root = script_dir.parent
    roundtrip_dir = script_dir / args.roundtrip_dir

    print("🔄 Roundtrip Translation Comparison")
    print("=" * 50)
    print(f"Project root: {project_root}")
    print(f"Roundtrip base directory: {roundtrip_dir}")
    print(f"Modules: {', '.join(args.modules)}")
    print()

    total_differences = 0
    all_results = {}

    # Helper to resolve original path per module
    def resolve_original_for_module(module: str) -> Path:
        if module == 'app':
            return project_root / 'app/src/main/res/values/strings.xml'
        # Prefer values-en for shared/wear if present, else fallback to values
        candidate_en = project_root / f'{module}/src/main/res/values-en/strings.xml'
        if candidate_en.exists():
            return candidate_en
        return project_root / f'{module}/src/main/res/values/strings.xml'

    # If user provided a single-module legacy mode (no modules flag), still work
    modules = args.modules if args.modules else ['app']

    for module in modules:
        original_path = resolve_original_for_module(module)
        print(f"📦 Module: {module}")
        print(f"📄 Original file: {original_path}")

        # Parse original file
        print("📖 Parsing original English strings...")
        original_strings = parse_strings_xml(original_path)
        if not original_strings:
            print("❌ Failed to parse original strings.xml file for module", module)
            continue
        print(f"✅ Found {len(original_strings)} strings in original file")

        # Compare each language for this module
        for lang in args.languages:
            roundtrip_path = roundtrip_dir / 'draft' / module / f"{lang}-to-en" / "strings.xml"
            if not roundtrip_path.exists():
                print(f"⚠️  {module}/{lang} missing → {roundtrip_path}")
                continue

            print(f"\n📖 Parsing {module}/{lang} roundtrip translation...")
            roundtrip_strings = parse_strings_xml(roundtrip_path)
            if not roundtrip_strings:
                print(f"❌ Failed to parse {module}/{lang} roundtrip file")
                continue
            print(f"✅ Found {len(roundtrip_strings)} strings in {module}/{lang} roundtrip file")

            # Compare strings
            differences = compare_strings(original_strings, roundtrip_strings, f"{module}/{lang}")

            # Store results for HTML report (key by module-lang)
            key = f"{module}-{lang}"
            all_results[key] = {
                'differences': differences,
                'total_strings': len(roundtrip_strings)
            }

            if not args.html:
                print_differences(differences, f"{module}/{lang}", args.show_all, not args.include_whitespace, not args.include_case, args.min_word_length)

            # Count meaningful differences for summary
            if not args.include_whitespace or not args.include_case or args.min_word_length > 0:
                meaningful_diffs = []
                for diff in differences:
                    if diff['type'] == 'text_difference':
                        orig_norm = diff.get('original_normalized', normalize_text(diff['original_text'], not args.include_case, args.min_word_length))
                        roundtrip_norm = diff.get('roundtrip_normalized', normalize_text(diff['roundtrip_text'], not args.include_case, args.min_word_length))
                        if orig_norm != roundtrip_norm:
                            meaningful_diffs.append(diff)
                    else:
                        meaningful_diffs.append(diff)
                total_differences += len(meaningful_diffs)
            else:
                total_differences += len(differences)

    if args.html:
        # Generate HTML report
        output_path = script_dir / args.output
        print(f"\n🌐 Generating HTML report: {output_path}")

        # For HTML report, original_file is less meaningful across modules; show base path
        html_file = generate_html_report(all_results, 'multiple modules', str(output_path), args.min_word_length)
        print(f"✅ HTML report generated: {html_file}")
        print(f"📖 Open the report in your browser to view the results")
    else:
        print(f"\n📊 Summary: {total_differences} total differences found across all modules and languages")
        if total_differences > 0:
            print("\n💡 Tips:")
            print("   - Review differences to assess translation quality")
            print("   - Focus on user-facing strings (translatable=true)")
            print("   - Consider context when evaluating differences")
            print("   - Use --show-all to see non-translatable string differences")
            print("   - Use --html to generate a clean HTML report")

if __name__ == "__main__":
    main()

