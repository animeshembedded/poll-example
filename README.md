# epoll-example
A simple program to test epoll 
Epoll sample.

Build and test.

Make sure you have cmake. This will only work on a Linux OS with epoll and accept4 support.

git clone https://github.com/animeshembedded/poll-example

cd epoll-example

mkdir build

cd build

cmake ../src

make
// To start the server at port 9090
./epoll 9090

// You can test by using netcat in another terminal
nc localhost 9090
// You can use a lanuchClient.sh for the multiple clients instant as example 
./lanuchClient.sh 5 9090 

A multi-threaded server which accepts bytes from the client and reverses them at arbitrary boundaries and sends it back to the client.

Most of the code for the epoll part of the tutorial is from [Banu Systems Blog]. 
The extension was making it multi threaded.
The code is a mix of C style (as it borrows from the blog) with some C++.

There are two threads connected by a ring buffer:

Thread 1: Accepts client connections and reads bytes from them in an event loop using epoll. For every read event it reads the bytes into a ring buffer entry and publishes it with the client FD.

Thread 2: It reads events of the ring buffer. For each entry it prints the bytes, reverses them in place and sends the reversed bytes back to the client.
Limitations.

The code is very simplistic and does not handle a lot of cases. 
The limitations and some potential solutions are:

We check for the string "exit" from the client to stop the server. The "exit" string might be split across two different epoll events and we will not detect this. This is handled by a proper protocol design.
The worker thread writes the reversed string to the client. It checks for an error but does not check if all bytes were written. The worker thread can also have it's own epoll loop where it waits for a write event when all bytes don't go through. One should still first attempt a write and only make an epoll call if all the bytes did not go through. 

There are a few tricky things here:

Balancing between polling the ring buffer (for more events to process) and making epoll calls is tricky.
The worker thread must copy any of the ring buffer entry data that it still needs before marking the entry processed. In our case that would be the FD for the socket and the data not sent yet. This is important because the producer thread could overwrite the entry before we manage to send the bytes to the client.

If a particular socket is waiting for a writable signal, the worker thread should not write data on that socket after a separate event is processed till the first pending data is successfully written. We can process the event and just append the data to our already pending data. This can be done by having a linked list of buffers or even a realloc + copy.
An important benefit of using a ring buffer is that there are no malloc/free calls in steady state. All the memory is pre-allocated and just re-used. We use static 4096k buffers to read client data. If multiple sizes of buffers are needed this design can be altered for close to zero allocations in steady state. 

This is easily achieved by using a length prefixed protocol:
Once the first 4/8 bytes (32bit/64 bit length) of a message are read(this can be done on the stack), the length of the buffer needed to hold the entire message is known.

We can pick an appropriately sized buffer from a pool of buffers and use it for the rest of the message. Once the entire message is read we can put a pointer to this buffer on the ring buffer and publish it. Beware of slowloris attacks with such an approach though. Malicious or slow/faulty clients could cause buffer exhaustion on the server. For eg: A bunch of clients could connect and say they have a 10 MB message to send. Once you allocate a 10 MB buffer they never send any data but your buffers get used up. Using timers to reclaim such buffers and disconnect misbehaving clients can help with these problems.

Whenever we are short on buffers we could check all the ring buffer entries that have been processed in this cycle. We can claim all those buffers and put them in our pool. With this technique we must claim buffers at least once per cycle of the ring buffer otherwise we will end up reclaiming buffers that are still in use. This accounting can be a bit tricky. There are other ways of exchanging buffer info without any sharing (false or otherwise).

A modern memory allocator like Jemalloc already uses slab allocation + buddy memory allocation to reuse buffers. We could use Jemalloc and just call malloc and free instead of maintaining our own buffer pool. Note: We still always call malloc and free on the same thread instead of across thread boundaries.
