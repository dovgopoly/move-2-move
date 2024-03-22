module billboard_address::billboard {
    use std::signer;
    use std::string::{String};
    use std::vector;

    const ENOT_OWNER: u64 = 1;

    const MAX_MESSAGES: u64 = 10;

    struct Billboard has key {
        messages: vector<Message>,
        oldest_index: u64
    }

    struct Message has store {
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
            return;
        };

        billboard.messages[billboard.oldest_index] = message;
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
        let billboard= borrow_global<Billboard>(@billboard_address);

        vector::rotate(&mut billboard.messages, billboard.oldest_index);

        billboard.messages
    }

    inline fun only_owner(owner: &signer) {
        assert!(signer::address_of(owner) == @billboard_address, ENOT_OWNER);
    }
}
