#!/usr/bin/env python3
"""
Import BookBuddy CSV, find missing ISBNs, fetch covers, and output for Firebase.
"""

import csv
import json
import time
import urllib.request
import urllib.parse
import os
from datetime import datetime

# Configuration
INPUT_CSV = os.path.expanduser("~/Library/Mobile Documents/com~apple~CloudDocs/BookBuddy 2026-01-05 191158.csv")
OUTPUT_JSON = os.path.expanduser("~/FamilyBooks/books_for_import.json")
PROGRESS_FILE = os.path.expanduser("~/FamilyBooks/import_progress.json")

# Rate limiting for Open Library API
REQUEST_DELAY = 0.5  # seconds between API calls


def load_progress():
    """Load previous progress if exists."""
    if os.path.exists(PROGRESS_FILE):
        with open(PROGRESS_FILE, 'r') as f:
            return json.load(f)
    return {"processed": {}, "last_index": 0}


def save_progress(progress):
    """Save progress to file."""
    with open(PROGRESS_FILE, 'w') as f:
        json.dump(progress, f, indent=2)


def search_open_library(title, author):
    """Search Open Library by title and author to find ISBN and cover."""
    try:
        params = []
        if title:
            params.append(f"title={urllib.parse.quote(title)}")
        if author:
            params.append(f"author={urllib.parse.quote(author)}")

        if not params:
            return None

        url = f"https://openlibrary.org/search.json?{'&'.join(params)}&limit=1"

        req = urllib.request.Request(url, headers={'User-Agent': 'FamilyBooks/1.0'})
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode())

        if not data.get('docs'):
            return None

        doc = data['docs'][0]

        result = {
            'isbn': '',
            'cover_url': ''
        }

        # Get ISBN
        if 'isbn' in doc and doc['isbn']:
            # Prefer ISBN-13 (starts with 978 or 979)
            for isbn in doc['isbn']:
                if len(isbn) == 13:
                    result['isbn'] = isbn
                    break
            if not result['isbn']:
                result['isbn'] = doc['isbn'][0]

        # Get cover URL
        if 'cover_i' in doc:
            result['cover_url'] = f"https://covers.openlibrary.org/b/id/{doc['cover_i']}-M.jpg"

        return result

    except Exception as e:
        print(f"  Error searching: {e}")
        return None


def lookup_isbn(isbn):
    """Look up book by ISBN to get cover."""
    try:
        # Clean ISBN
        isbn = isbn.replace('-', '').replace(' ', '')

        url = f"https://openlibrary.org/api/books?bibkeys=ISBN:{isbn}&format=json&jscmd=data"

        req = urllib.request.Request(url, headers={'User-Agent': 'FamilyBooks/1.0'})
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode())

        key = f"ISBN:{isbn}"
        if key not in data:
            # Try search instead
            return search_by_isbn(isbn)

        book_data = data[key]

        cover_url = ''
        if 'cover' in book_data:
            cover_url = book_data['cover'].get('medium', book_data['cover'].get('small', ''))

        return {'cover_url': cover_url}

    except Exception as e:
        print(f"  Error looking up ISBN: {e}")
        return None


def search_by_isbn(isbn):
    """Search Open Library by ISBN to get cover."""
    try:
        url = f"https://openlibrary.org/search.json?isbn={isbn}&limit=1"

        req = urllib.request.Request(url, headers={'User-Agent': 'FamilyBooks/1.0'})
        with urllib.request.urlopen(req, timeout=10) as response:
            data = json.loads(response.read().decode())

        if not data.get('docs'):
            return None

        doc = data['docs'][0]

        cover_url = ''
        if 'cover_i' in doc:
            cover_url = f"https://covers.openlibrary.org/b/id/{doc['cover_i']}-M.jpg"

        return {'cover_url': cover_url}

    except Exception as e:
        print(f"  Error searching by ISBN: {e}")
        return None


def parse_bookbuddy_csv(filepath):
    """Parse BookBuddy CSV export."""
    books = []

    with open(filepath, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)

        for row in reader:
            # Extract relevant fields
            book = {
                'title': row.get('Title', '').strip(),
                'authors': row.get('Author', '').strip(),
                'isbn': row.get('ISBN', '').strip().replace('-', ''),
                'publisher': row.get('Publisher', '').strip(),
                'publishDate': row.get('Year Published', '').strip(),
                'numberOfPages': row.get('Number of Pages', '').strip(),
                'notes': row.get('Notes', '').strip(),
                'coverURL': '',  # Will be fetched
                'addedBy': 'BookBuddy Import',
                'addedAt': datetime.now().isoformat(),
                'copies': 1,
                'readingStatus': '',
                'isWishlist': row.get('Wish List', '0') == '1'
            }

            # Map reading status
            status = row.get('Status', '').strip()
            if status == 'Read':
                book['readingStatus'] = 'Read'
            elif status == 'Reading':
                book['readingStatus'] = 'Reading'
            elif status == 'Unread' or status == 'Want to Read':
                book['readingStatus'] = 'Want to Read'

            if book['title']:  # Only add if has title
                books.append(book)

    return books


def main():
    print("=" * 60)
    print("BookBuddy Import Script")
    print("=" * 60)

    # Load previous progress
    progress = load_progress()
    print(f"\nLoaded progress: {len(progress['processed'])} books already processed")

    # Parse CSV
    print(f"\nParsing CSV: {INPUT_CSV}")
    books = parse_bookbuddy_csv(INPUT_CSV)
    print(f"Found {len(books)} books in CSV")

    # Process books
    processed_books = []

    for i, book in enumerate(books):
        title = book['title']

        # Create unique key for progress tracking
        book_key = f"{title}|{book['authors']}"

        # Check if already processed
        if book_key in progress['processed']:
            cached = progress['processed'][book_key]
            book['isbn'] = cached.get('isbn', book['isbn'])
            book['coverURL'] = cached.get('coverURL', '')
            processed_books.append(book)
            continue

        print(f"\n[{i+1}/{len(books)}] {title[:50]}...")

        isbn = book['isbn']
        cover_url = ''

        if isbn:
            # Has ISBN - just need cover
            print(f"  ISBN: {isbn} - looking up cover...")
            result = lookup_isbn(isbn)
            if result and result.get('cover_url'):
                cover_url = result['cover_url']
                print(f"  Found cover!")
            else:
                # Try searching by title/author as fallback
                print(f"  No cover from ISBN, trying search...")
                result = search_open_library(title, book['authors'])
                if result and result.get('cover_url'):
                    cover_url = result['cover_url']
                    print(f"  Found cover via search!")
        else:
            # No ISBN - search for it
            print(f"  No ISBN - searching Open Library...")
            result = search_open_library(title, book['authors'])
            if result:
                if result.get('isbn'):
                    isbn = result['isbn']
                    print(f"  Found ISBN: {isbn}")
                if result.get('cover_url'):
                    cover_url = result['cover_url']
                    print(f"  Found cover!")
            else:
                print(f"  No results found")

        book['isbn'] = isbn
        book['coverURL'] = cover_url
        processed_books.append(book)

        # Save progress
        progress['processed'][book_key] = {
            'isbn': isbn,
            'coverURL': cover_url
        }
        progress['last_index'] = i

        if (i + 1) % 10 == 0:
            save_progress(progress)
            print(f"\n  Progress saved ({i+1} books processed)")

        # Rate limiting
        time.sleep(REQUEST_DELAY)

    # Final save
    save_progress(progress)

    # Generate Firebase-ready JSON
    print(f"\n{'=' * 60}")
    print("Generating output...")

    # Convert to Firebase format
    firebase_books = {}
    for i, book in enumerate(processed_books):
        key = f"book_{i:04d}"
        firebase_books[key] = {
            'isbn': book['isbn'],
            'title': book['title'],
            'authors': book['authors'],
            'publisher': book['publisher'],
            'publishDate': book['publishDate'],
            'numberOfPages': book['numberOfPages'],
            'coverURL': book['coverURL'],
            'notes': book['notes'],
            'addedBy': book['addedBy'],
            'addedAt': int(datetime.now().timestamp() * 1000),
            'copies': book['copies'],
            'readingStatus': book['readingStatus'],
            'isWishlist': book['isWishlist']
        }

    with open(OUTPUT_JSON, 'w', encoding='utf-8') as f:
        json.dump(firebase_books, f, indent=2, ensure_ascii=False)

    print(f"\nOutput saved to: {OUTPUT_JSON}")

    # Stats
    with_isbn = sum(1 for b in processed_books if b['isbn'])
    with_cover = sum(1 for b in processed_books if b['coverURL'])

    print(f"\n{'=' * 60}")
    print("SUMMARY")
    print(f"{'=' * 60}")
    print(f"Total books:     {len(processed_books)}")
    print(f"With ISBN:       {with_isbn} ({100*with_isbn/len(processed_books):.1f}%)")
    print(f"With cover:      {with_cover} ({100*with_cover/len(processed_books):.1f}%)")
    print(f"Missing ISBN:    {len(processed_books) - with_isbn}")
    print(f"Missing cover:   {len(processed_books) - with_cover}")


if __name__ == '__main__':
    main()
