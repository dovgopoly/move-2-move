module dutch_auction_address::dutch_auction {
    use std::string::{Self, String};
    use std::option;
    use std::signer;
    use aptos_framework::event;
    use aptos_framework::object::{Self, Object, TransferRef};
    use aptos_framework::fungible_asset::{Metadata};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aptos_token_objects::collection;
    use aptos_token_objects::token::{Self, Token};
    #[test_only]
    use std::vector;
    #[test_only]
    use aptos_std::debug;
    #[test_only]
    use aptos_framework::event::emitted_events;
    #[test_only]
    use aptos_framework::fungible_asset;
    #[test_only]
    use aptos_framework::fungible_asset::FungibleStore;

    const ENOT_OWNER: u64 = 1;
    const ENOT_ON_SALE: u64 = 2;
    const EINVALID_AUCTION_OBJECT: u64 = 3;
    const EOUTDATED_AUCTION: u64 = 4;

    const DUTCH_AUCTION_COLLECTION_SUPPLY: u64 = 100;
    const DUTCH_AUCTION_COLLECTION_NAME: vector<u8> = b"DUTCH_AUCTION_NAME";
    const DUTCH_AUCTION_COLLECTION_DESCRIPTION: vector<u8> = b"DUTCH_AUCTION_DESCRIPTION";
    const DUTCH_AUCTION_COLLECTION_URI: vector<u8> = b"DUTCH_AUCTION_URI";

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct Auction has key, copy {
        sell_token: Object<Token>,
        buy_token: Object<Metadata>,
        max_price: u64,
        min_price: u64,
        duration: u64,
        started_at: u64
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct TokenConfig has key {
        transfer_ref: TransferRef
    }

    #[event]
    struct AuctionCreatedEvent has drop, store {
        auction: Object<Auction>
    }

    fun init_module(creator: &signer) {
        collection::create_fixed_collection(
            creator,
            string::utf8(DUTCH_AUCTION_COLLECTION_DESCRIPTION),
            DUTCH_AUCTION_COLLECTION_SUPPLY,
            string::utf8(DUTCH_AUCTION_COLLECTION_NAME),
            option::none(),
            string::utf8(DUTCH_AUCTION_COLLECTION_URI),
        );
    }

    entry public fun bid(customer: &signer, auction: Object<Auction>) acquires Auction, TokenConfig {
        let auction_address = object::object_address(&auction);

        assert!(exists<Auction>(auction_address) && exists<TokenConfig>(auction_address), EINVALID_AUCTION_OBJECT);

        let auction = borrow_global_mut<Auction>(auction_address);

        assert!(object::is_owner(auction.sell_token, @dutch_auction_address), ENOT_ON_SALE);

        let current_price = must_have_price(auction);

        primary_fungible_store::transfer(customer, auction.buy_token, @dutch_auction_address, current_price);

        let transfer_ref = &borrow_global_mut<TokenConfig>(auction_address).transfer_ref;
        let linear_transfer_ref = object::generate_linear_transfer_ref(transfer_ref);

        object::transfer_with_ref(linear_transfer_ref, signer::address_of(customer));
    }

    entry public fun start_auction(
        owner: &signer,
        token_name: String,
        token_description: String,
        token_uri: String,
        buy_token: Object<Metadata>,
        max_price: u64,
        min_price: u64,
        duration: u64
    ) {
        only_owner(owner);

        let sell_token_ctor = token::create_named_token(
            owner,
            string::utf8(DUTCH_AUCTION_COLLECTION_NAME),
            token_description,
            token_name,
            option::none(),
            token_uri,
        );
        let transfer_ref = object::generate_transfer_ref(&sell_token_ctor);
        let sell_token = object::object_from_constructor_ref<Token>(&sell_token_ctor);

        let auction = Auction {
            sell_token,
            buy_token,
            max_price,
            min_price,
            duration,
            started_at: timestamp::now_seconds()
        };

        let auction_ctor = object::create_object(signer::address_of(owner));
        let auction_signer = object::generate_signer(&auction_ctor);

        move_to(&auction_signer, auction);
        move_to(&auction_signer, TokenConfig { transfer_ref });

        let auction = object::object_from_constructor_ref<Auction>(&auction_ctor);

        event::emit(AuctionCreatedEvent { auction });
    }

    fun must_have_price(auction: &Auction): u64 {
        let time_now = timestamp::now_seconds();

        assert!(auction.started_at + auction.duration >= time_now, EOUTDATED_AUCTION);

        let time_passed = time_now - auction.started_at;
        let discount = ((auction.max_price - auction.min_price) * time_passed) / auction.duration;

        auction.max_price - discount
    }

    inline fun only_owner(owner: &signer) {
        assert!(signer::address_of(owner) == @dutch_auction_address, ENOT_OWNER);
    }

    #[test(aptos_framework = @std, owner = @dutch_auction_address, alice = @0x1234, bob = @0x5678)]
    fun test_auction_happy_path(aptos_framework: &signer, owner: &signer, alice: &signer, bob: &signer) acquires Auction, TokenConfig {
        init_module(owner);

        let feature = std::features::get_aggregator_v2_api_feature();
        std::features::change_feature_flags(aptos_framework, vector[], vector[feature]);

        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::update_global_time_for_test_secs(1000);

        let (buy_token, _alice_store, _bob_store) = create_ft(owner, alice, bob);

        start_auction(
            owner,
            string::utf8(b"TOKEN_NAME"),
            string::utf8(b"TOKEN_DESCRIPTION"),
            string::utf8(b"TOKEN_URI"),
            buy_token,
            10,
            1,
            300
        );

        let auction_created_events = event::emitted_events<AuctionCreatedEvent>();
        let auction = vector::borrow(&auction_created_events, 0).auction;

        bid(alice, auction);
    }

    #[test_only]
    fun create_ft(owner: &signer, alice: &signer, bob: &signer): (Object<Metadata>, Object<FungibleStore>, Object<FungibleStore>) {
        let ctor_ref = object::create_named_object(owner, b"T");

        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &ctor_ref,
            option::none<u128>(),
            string::utf8(b"T"),
            string::utf8(b"T"),
            18,
            string::utf8(b"URI"),
            string::utf8(b"URI")
        );

        let metadata = object::object_from_constructor_ref<Metadata>(&ctor_ref);

        let alice_store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(alice), metadata);
        let bob_store = primary_fungible_store::ensure_primary_store_exists(signer::address_of(bob), metadata);

        let mint_ref = fungible_asset::generate_mint_ref(&ctor_ref);

        fungible_asset::mint_to(&mint_ref, alice_store, 50);
        fungible_asset::mint_to(&mint_ref, bob_store, 30);

        primary_fungible_store::transfer(alice, metadata, signer::address_of(bob), 10);

        (metadata, alice_store, bob_store)
    }
}
