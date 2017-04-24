# NAME

Stor - Save/retrieve a file to/from primary storage

# SYNOPSIS

    # retrieve a file
    curl http://stor-url/946a5ec1d49e0d7825489b1258476fdd66a3e9370cc406c2981a4dc3cd7f4e4f

    # store a file
    curl -X POST --data @my_file http://stor-url/946a5ec1d49e0d7825489b1258476fdd66a3e9370cc406c2981a4dc3cd7f4e4f

# DESCRIPTION

Stor is an HTTP API to primary storage. You provide a SHA256 hash and get the file contents, or you provide a SHA256 hash and a file contents and it gets stored to primary storages.

## Service Responsibility

- provide HTTP API
- redundancy support
- resource allocation

## API

### HEAD /:sha

### GET /:sha

#### 200 OK

File exists

Headers:

    Content-Length - file size of file

GET return content of file in body

#### 404 Not Found

Sample not found

### POST /:sha

save sample to n-tuple of storages

For authentication use Basic access authentication

compare SHA and sha256 of file

#### 200 OK

file exists

Headers:

Body:

    {
        "locations": {
            "nfs":  ["server1:/some_path/to/file", "server2:/another_path/to/file"],
            "cifs": ["\\\\server1\\share\\path\\to\\file", "\\\\server2\\share\\path\\to\\file"]
        }
    }

#### 201 Created

file was added to all storages

Body:

    {
        "locations": {
            "nfs":  ["server1:/some_path/to/file", "server2:/another_path/to/file"],
            "cifs": ["\\\\server1\\share\\path\\to\\file", "\\\\server2\\share\\path\\to\\file"]
        }
    }

#### 401 Unauthorized

Bad authentication

#### 412 Precondition Failed

content mismatch - sha256 of content not equal SHA

#### 507 Insufficient Storage

There is not enough space on storage to save the file.

Headers:

    Content-Sha-256 - sha256 of content

### GET /status

#### 200 OK

all storages are available

#### 503

some storage is unavailable

### GET /storages

return list of storages and disk usage

## Redundancy Support

for redundancy we need support defined n-tuple of storages

n-tuple of storages must works minimal 1 for GET and all for POST

pseudo-example of n-tuple of storages definition:

    [
        ["storage1", "storage2"],
        ["storage3", "storage4"]
    ]

in pseudo-example case we must new sample save to storage1 and storage2 or storage3 and storage4

## Resource Allocation

save samples to n-tuple of storages with enough of resources => service responsibility is check disk usage

nice to have is balanced samples to all storages equally

# LICENSE

Copyright (C) Avast Software

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Miroslav Tynovsky <tynovsky@avast.com>
