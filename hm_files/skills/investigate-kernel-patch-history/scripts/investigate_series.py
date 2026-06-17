import subprocess
import re
import os
import mailbox
import email
from email.header import decode_header
import urllib.parse
import sys

def decode_mime_word(s):
    if not s:
        return ""
    try:
        decoded_fragments = decode_header(s)
        fragments = []
        for fragment, encoding in decoded_fragments:
            if isinstance(fragment, bytes):
                if encoding:
                    fragments.append(fragment.decode(encoding, errors='replace'))
                else:
                    fragments.append(fragment.decode('utf-8', errors='replace'))
            else:
                fragments.append(fragment)
        return "".join(fragments)
    except Exception as e:
        return str(s)

def get_message_body(msg):
    if msg.is_multipart():
        for part in msg.walk():
            ctype = part.get_content_type()
            cdisp = str(part.get('Content-Disposition'))
            if ctype == 'text/plain' and 'attachment' not in cdisp:
                payload = part.get_payload(decode=True)
                if payload:
                    charset = part.get_content_charset()
                    if charset:
                        return payload.decode(charset, errors='replace')
                    else:
                        return payload.decode('utf-8', errors='replace')
        # Fallback to first text part if no text/plain found
        for part in msg.walk():
            ctype = part.get_content_type()
            if 'text/' in ctype:
                payload = part.get_payload(decode=True)
                if payload:
                    charset = part.get_content_charset()
                    if charset:
                        return payload.decode(charset, errors='replace')
                    else:
                        return payload.decode('utf-8', errors='replace')
        return ""
    else:
        payload = msg.get_payload(decode=True)
        if payload:
            charset = msg.get_content_charset()
            if charset:
                return payload.decode(charset, errors='replace')
            else:
                return payload.decode('utf-8', errors='replace')
        return ""

def parse_mbox(mbox_path):
    mbox = mailbox.mbox(mbox_path)
    messages = {}
    roots = []
    
    # First pass: collect all messages by message-id
    for key, msg in mbox.items():
        msg_id = msg.get('Message-ID', '').strip('<>')
        in_reply_to = msg.get('In-Reply-To', '').strip('<>')
        
        subject = decode_mime_word(msg.get('Subject', ''))
        from_header = decode_mime_word(msg.get('From', ''))
        date = msg.get('Date', '')
        body = get_message_body(msg)

        m_data = {
            'id': msg_id,
            'in_reply_to': in_reply_to,
            'subject': subject,
            'from': from_header,
            'date': date,
            'body': body,
            'children': [],
            'raw_message': msg
        }
        
        messages[msg_id] = m_data
        
    # Second pass: build tree
    for msg_id, msg_data in messages.items():
        parent_id = msg_data['in_reply_to']
        if parent_id and parent_id in messages:
            messages[parent_id]['children'].append(msg_data)
        else:
            roots.append(msg_data)
            
    return roots, messages

def print_thread_markdown(roots, level=1, outfile=None):
    for root in roots:
        header_prefix = '#' * (level + 1)
        print(f"{header_prefix} {root['subject']}", file=outfile)
        print(f"- **From:** {root['from']}", file=outfile)
        print(f"- **Date:** {root['date']}", file=outfile)
        print(f"- **Message-ID:** `{root['id']}`", file=outfile)
        print("", file=outfile)
        print("```text", file=outfile)
        print(root['body'], file=outfile)
        print("```", file=outfile)
        print("", file=outfile)
        
        if root['children']:
            print_thread_markdown(root['children'], level + 1, outfile)

def extract_links_from_body(body):
    urls = re.findall(r'(https?://\S+)', body)
    cleaned_urls = []
    for u in urls:
        u = u.rstrip('.,;)]>')
        cleaned_urls.append(u)
    return cleaned_urls

def is_series_url(url):
    # Restrictive check: URL must contain a message ID that looks like a series or patch.
    # We want to match URLs from patch.msgid.link or lore.kernel.org that represent series versions.
    # URLs to individual messages or replies are excluded unless they look like they are a patch or series cover letter.
    if 'patch.msgid.link' in url:
        return True
    
    if 'lore.kernel.org' in url:
        # e.g. https://lore.kernel.org/bpf/20250501032718.65476-1-alexei.starovoitov@gmail.com/
        # Check if it has a patch index or date in the message ID.
        # Message IDs for series usually contain a date and a sequence number, e.g. 20250501032718.65476-1
        parts = url.split('/')
        if len(parts) >= 5:
            msg_id = parts[-1] if parts[-1] else parts[-2]
            # If it's a series message ID, it usually contains a date (YYYYMMDD...) and a sequence number.
            if '-' in msg_id and re.search(r'\d{8}', msg_id):
                return True
            # Also if it's a patch-id link or a specific message ID that we know is a series version
            if 'v' in msg_id.lower() and ('patch' in msg_id.lower() or 'series' in msg_id.lower()):
                return True
                
    return False

def is_critical_context(body, url):
    idx = body.find(url)
    if idx == -1:
        return False
    
    start = max(0, idx - 200)
    end = min(len(body), idx + len(url) + 200)
    context = body[start:end]
    
    critical_keywords = ['supersedes', 'replaces', 'based on', 'fix for', 'discussion in', 'previous version', 'v1']
    for kw in critical_keywords:
        if kw in context.lower():
            return True
    return False

def download_series(version_name, url, output_dir):
    url = url.rstrip('/')
    msg_id = url.split('/')[-1]
    msg_id = urllib.parse.unquote(msg_id)
    
    if not msg_id or '@' not in msg_id and '.' not in msg_id:
        print(f"Skipping invalid message ID {msg_id} from URL {url}")
        return None

    cmd = ['b4', 'mbox', '-o', output_dir, msg_id]
    print(f"Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Failed to download series {version_name}: {result.stderr}")
        return None
    
    filename = f"{msg_id}.mbx"
    filepath = os.path.join(output_dir, filename)
    if os.path.exists(filepath):
        return filepath
    
    files = os.listdir(output_dir)
    for f in files:
        if f.endswith('.mbx') and msg_id in f:
            return os.path.join(output_dir, f)
            
    print(f"Could not find downloaded mbox file for {version_name} in {output_dir}")
    return None

def investigate_commit(commit, output_md_path, mbox_dir='/tmp'):
    fetched_urls = set()
    versions_to_fetch = []
    references = []
    critical_references = []
    
    # Ensure output directory exists
    os.makedirs(os.path.dirname(os.path.abspath(output_md_path)), exist_ok=True)
    os.makedirs(mbox_dir, exist_ok=True)

    # Initial versions from b4 dig --all-series
    cmd = ['b4', 'dig', '-c', commit, '--all-series']
    print(f"Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    output = result.stdout + "\n" + result.stderr
    print("Initial b4 dig output:")
    print(output)
    
    lines = output.splitlines()
    versions = []
    current_version = None
    
    for line in lines:
        match = re.search(r'^\s*(v\d+):\s+(.*)', line)
        if match:
            if current_version:
                versions.append(current_version)
            current_version = {'name': match.group(1), 'desc': match.group(2), 'url': None}
        elif current_version and 'https://' in line:
            url_match = re.search(r'(https?://\S+)', line)
            if url_match:
                current_version['url'] = url_match.group(1)
                versions.append(current_version)
                current_version = None
                
    if current_version:
        versions.append(current_version)
        
    print(f"Initial versions found by b4 dig: {versions}")
    
    # Add initial versions to our fetch queue
    for v in versions:
        if v['url'] and v['url'] not in fetched_urls:
            versions_to_fetch.append(v)
            fetched_urls.add(v['url'])
            
    processed_urls = set()
    
    with open(output_md_path, 'w', encoding='utf-8') as outfile:
        print(f"# Mailing List History for Commit: {commit}", file=outfile)
        print("", file=outfile)
        
        idx = 0
        while idx < len(versions_to_fetch):
            v = versions_to_fetch[idx]
            idx += 1
            
            # Normalize URL to avoid duplicates
            url = v['url'].rstrip('/')
            if url in processed_urls:
                continue
                
            processed_urls.add(url)
            
            print(f"## Version {v.get('name', 'DISCOVERED')}", file=outfile)
            print(f"Description: {v.get('desc', 'Discovered from links in previous threads')}", file=outfile)
            print(f"URL: {url}", file=outfile)
            print("", file=outfile)
            
            mbox_path = download_series(v.get('name', 'DISCOVERED'), url, mbox_dir)
            if mbox_path:
                print(f"Parsing mbox: {mbox_path}", file=outfile)
                roots, messages = parse_mbox(mbox_path)
                print(f"Found {len(messages)} messages in this version thread.", file=outfile)
                print("", file=outfile)
                print_thread_markdown(roots, level=2, outfile=outfile)
                print("", file=outfile)
                
                # Check roots for cover letter and patches to find links to previous versions or other context
                for root in roots:
                    body = root.get('body', '')
                    urls_in_body = extract_links_from_body(body)
                    for u in urls_in_body:
                        u_clean = u.rstrip('/')
                        if is_series_url(u_clean):
                            if u_clean not in fetched_urls and u_clean not in processed_urls:
                                print(f"Discovered new version URL from text: {u_clean}")
                                fetched_urls.add(u_clean)
                                versions_to_fetch.append({
                                    'url': u_clean,
                                    'desc': f'Discovered from {v.get("name", "thread")} links',
                                    'name': f'DISCOVERED_{len(versions_to_fetch)}'
                                })
                        else:
                            # It's a reference to another thread/discussion
                            if u_clean not in references:
                                references.append(u_clean)
                                if is_critical_context(body, u):
                                    print(f"Discovered CRITICAL reference from text: {u_clean}")
                                    if u_clean not in fetched_urls and u_clean not in processed_urls:
                                        critical_references.append(u_clean)
                                        fetched_urls.add(u_clean)
                                        # We treat critical references as series versions to fetch them via b4 mbox if possible, or just download them
                                        versions_to_fetch.append({
                                            'url': u_clean,
                                            'desc': f'Critical context discovered from {v.get("name", "thread")}',
                                            'name': f'CRITICAL_{len(critical_references)}'
                                        })
                                                                else:
                                    print(f"Discovered reference from text: {u_clean}")
                                    
            else:
                print("Failed to download or find mbox for this version.", file=outfile)
                
            print("", file=outfile)
            print("---", file=outfile)
            print("", file=outfile)

        # Print references section at the end
        if references:
            print("# References and Other Context Threads", file=outfile)
            print("", file=outfile)
            print("The following external threads/links were referenced in the discussions above. They may provide additional context:", file=outfile)
            print("", file=outfile)
            for ref in references:
                print(f"- {ref}", file=outfile)
            print("", file=outfile)
            
        if critical_references:
            print("# Proactively Fetched Critical References", file=outfile)
            print("", file=outfile)
            print("The following references were deemed critical and were fetched proactively:", file=outfile)
            print("", file=outfile)
            for ref in critical_references:
                print(f"- {ref}", file=outfile)
            print("", file=outfile)

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python3 investigate_series.py <commit_hash> <output_path>")
        sys.exit(1)
        
    commit = sys.argv[1]
    output_md_path = sys.argv[2]
    mbox_dir = '/tmp/mboxes_v4' # Use a dedicated directory for mboxes
    
    investigate_commit(commit, output_md_path, mbox_dir)
    print(f"History written to {output_md_path}")
