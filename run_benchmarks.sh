erl -make
for thread in {1..64}
do
    echo "---"
    echo "> test_log_in, $thread thread(s)"
    for iteration in {1..30}
    do
      echo "iteration $iteration..."
      erl -pa ebin +P 134217727 +S $thread -noshell -s benchmark test_log_in 10000 100 100 -s init stop
    done
    echo "---"
    echo "> test_send_message, $thread thread(s)"
    for iteration in {1..30}
    do
      echo "iteration $iteration..."
      erl -pa ebin +P 134217727 +S $thread -noshell -s benchmark test_send_message 5000 5000 100 -s init stop
    done
done
