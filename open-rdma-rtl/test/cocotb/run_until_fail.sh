while true; do
    make run

    if [ $? -ne 0 ]; then
        break
    fi
done