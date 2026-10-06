package org.sbook.search;

final class SearchResult {
    final String path;
    final String name;
    final String snippet;

    SearchResult(String path, String name, String snippet) {
        this.path = path;
        this.name = name;
        this.snippet = snippet == null ? "" : snippet;
    }
}

