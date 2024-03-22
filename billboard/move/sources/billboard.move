module billboard_address::billboard {
    use std::signer;
    use std::string::{String};
    use std::vector;

    const ENOT_OWNER: u64 = 1;

    const MAX_MESSAGES: u64 = 5;

    struct Billboard has key {
        messages: vector<Message>,
        oldest_index: u64
    }

    struct Message has store, copy, drop {
        sender: address,
        message: String
    }

    fun init_module(owner: &signer) {
        move_to(owner, Billboard { messages: vector[], oldest_index: 0 })
    }

    public entry fun add_message(sender: &signer, message: String) acquires Billboard {
        let message = Message {
            sender: signer::address_of(sender),
            message,
        };

        let billboard = borrow_global_mut<Billboard>(@billboard_address);

        if (vector::length(&billboard.messages) < MAX_MESSAGES) {
            vector::push_back(&mut billboard.messages, message);
            return
        };

        *vector::borrow_mut(&mut billboard.messages, billboard.oldest_index) = message;
        billboard.oldest_index = (billboard.oldest_index + 1) % MAX_MESSAGES;
    }

    public entry fun clear(owner: &signer) acquires Billboard {
        only_owner(owner);

        let billboard = borrow_global_mut<Billboard>(@billboard_address);

        billboard.messages = vector[];
        billboard.oldest_index = 0;
    }

    #[view]
    public fun get_messages(): vector<Message> acquires Billboard {
        let billboard= borrow_global_mut<Billboard>(@billboard_address);

        vector::rotate(&mut billboard.messages, billboard.oldest_index);

        billboard.messages
    }

    inline fun only_owner(owner: &signer) {
        assert!(signer::address_of(owner) == @billboard_address, ENOT_OWNER);
    }

    #[test(owner = @billboard_address, alice = @0x1234, bob = @0xb0b)]
    fun test_billboard_happy_path(owner: &signer, alice: &signer, bob: &signer) acquires Billboard {
        use std::string;

        init_module(owner);

        let msgs = get_messages();

        assert!(vector::length(&msgs) == 0, 1);

        let alice_message = string::utf8(b"alice's message");
        let bob_message = string::utf8(b"bob's message");

        add_message(alice, alice_message);
        add_message(bob, bob_message);

        msgs = get_messages();

        assert!(vector::length(&msgs) == 2, 1);

        assert!(vector::borrow(&msgs, 0).message == alice_message, 1);
        assert!(vector::borrow(&msgs, 0).sender == signer::address_of(alice), 1);

        assert!(vector::borrow(&msgs, 1).message == bob_message, 1);
        assert!(vector::borrow(&msgs, 1).sender == signer::address_of(bob), 1);

        add_message(bob, bob_message);
        add_message(bob, bob_message);
        add_message(bob, bob_message);
        add_message(bob, bob_message);

        msgs = get_messages();

        assert!(vector::length(&msgs) == 5, 1);

        assert!(vector::borrow(&msgs, 0).message == bob_message, 1);
        assert!(vector::borrow(&msgs, 0).sender == signer::address_of(bob), 1);

        clear(owner);

        msgs = get_messages();

        assert!(vector::length(&msgs) == 0, 1);
    }
}
