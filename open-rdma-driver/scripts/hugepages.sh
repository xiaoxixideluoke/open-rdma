#!/bin/bash

allocate_hugepages() {
    local total_memory_mb=$1
    
    original_hugepages=$(cat /proc/sys/vm/nr_hugepages)
    huge_page_size_kb=$(grep Hugepagesize /proc/meminfo | awk '{print $2}')
    huge_page_size_mb=$((huge_page_size_kb / 1024))
    num_pages=$((total_memory_mb / huge_page_size_mb))
    
    echo "Allocating $num_pages huge pages (${total_memory_mb}MB total, ${huge_page_size_mb}MB per page)..."
    
    echo $num_pages > /proc/sys/vm/nr_hugepages
    
    allocated=$(cat /proc/sys/vm/nr_hugepages)
    
    if [ "$allocated" -lt "$num_pages" ]; then
        echo "Failed to allocate requested huge pages. Requested: $num_pages, Allocated: $allocated"
        echo "Reverting to original setting: $original_hugepages huge pages"
        echo $original_hugepages > /proc/sys/vm/nr_hugepages
        return 1
    else
        actual_memory=$((allocated * huge_page_size_mb))
        echo "Successfully allocated $allocated huge pages (${actual_memory}MB)"
        return 0
    fi
}

deallocate_hugepages() {
    echo "Deallocating huge pages..."
    echo 0 > /proc/sys/vm/nr_hugepages
    
    allocated=$(cat /proc/sys/vm/nr_hugepages)
    echo "Huge pages remaining: $allocated"
}

case "$1" in
    "alloc")
        if [ -z "$2" ]; then
            echo "Usage: $0 alloc <memory_in_MB>"
            exit 1
        fi
        allocate_hugepages "$2"
        exit $?
        ;;
    "dealloc")
        deallocate_hugepages
        ;;
    *)
        echo "Usage: $0 {alloc <memory_in_MB>|dealloc}"
        exit 1
        ;;
esac

exit 0

