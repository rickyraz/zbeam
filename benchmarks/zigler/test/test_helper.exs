# Threaded stress is quarantined after an observed VM segfault; run only in a disposable VM.
ExUnit.start(exclude: [threaded_unverified: true])
