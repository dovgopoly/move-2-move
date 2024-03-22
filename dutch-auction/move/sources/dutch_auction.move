module dutch_auction_address::dutch_auction {
    use std::error;
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

    const ENOT_OWNER: u64 = 1;
    const ENOT_ON_SALE: u64 = 2;
    const EINVALID_AUCTION_OBJECT: u64 = 3;
    const EOUTDATED_AUCTION: u64 = 4;
    const EINVALID_PRICES: u64 = 5;
    const EINVALID_DURATION: u64 = 6;

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
    struct AuctionCreated has drop, store {
        auction: Object<Auction>
    }

    fun init_module(creator: &signer) {
        collection::create_unlimited_collection(
            creator,
            string::utf8(DUTCH_AUCTION_COLLECTION_DESCRIPTION),
            string::utf8(DUTCH_AUCTION_COLLECTION_NAME),
            option::none(),
            string::utf8(DUTCH_AUCTION_COLLECTION_URI),
        );
    }

    entry public fun bid(customer: &signer, auction: Object<Auction>) acquires Auction, TokenConfig {
        let auction_address = object::object_address(&auction);

        assert!(
            exists<Auction>(auction_address) && exists<TokenConfig>(auction_address),
            error::invalid_argument(EINVALID_AUCTION_OBJECT)
        );

        let auction = borrow_global_mut<Auction>(auction_address);

        assert!(
            object::is_owner(auction.sell_token, @dutch_auction_address),
            error::unavailable(ENOT_ON_SALE)
        );

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

        assert!(max_price >= min_price, error::invalid_argument(EINVALID_PRICES));
        assert!(max_price >= min_price, error::invalid_argument(EINVALID_DURATION));

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

        event::emit(AuctionCreated { auction });
    }

    fun must_have_price(auction: &Auction): u64 {
        let time_now = timestamp::now_seconds();

        assert!(time_now <= auction.started_at + auction.duration, error::unavailable(EOUTDATED_AUCTION));

        let time_passed = time_now - auction.started_at;
        let discount = ((auction.max_price - auction.min_price) * time_passed) / auction.duration;

        auction.max_price - discount
    }

    inline fun only_owner(owner: &signer) {
        assert!(signer::address_of(owner) == @dutch_auction_address, error::permission_denied(ENOT_OWNER));
    }

    #[test(aptos_framework = @std, owner = @dutch_auction_address, customer = @0x1337)]
    fun test_auction_happy_path(
        aptos_framework: &signer,
        owner: &signer,
        customer: &signer
    ) acquires Auction, TokenConfig {
        use std::features;
        use std::vector;

        init_module(owner);

        let feature = features::get_aggregator_v2_api_feature();
        features::change_feature_flags(aptos_framework, vector[], vector[feature]);

        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::update_global_time_for_test_secs(1000);

        let buy_token = setup_buy_token(owner, customer);

        start_auction(
            owner,
            string::utf8(b"token_name"),
            string::utf8(b"token_description"),
            string::utf8(b"token_uri"),
            buy_token,
            10,
            1,
            300
        );

        let auction_created_events = event::emitted_events<AuctionCreated>();
        let auction = vector::borrow(&auction_created_events, 0).auction;

        assert!(primary_fungible_store::balance(signer::address_of(customer), buy_token) == 50, 1);

        bid(customer, auction);

        primary_fungible_store::transfer(customer, buy_token, @dutch_auction_address, 20);

        assert!(primary_fungible_store::balance(signer::address_of(customer), buy_token) == 40, 1);
    }

    #[test_only]
    fun setup_buy_token(owner: &signer, customer: &signer): Object<Metadata> {
        use aptos_framework::fungible_asset;

        let ctor_ref = object::create_sticky_object(signer::address_of(owner));

        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &ctor_ref,
            option::none<u128>(),
            string::utf8(b"token"),
            string::utf8(b"symbol"),
            0,
            string::utf8(b"icon_uri"),
            string::utf8(b"project_uri")
        );

        let metadata = object::object_from_constructor_ref<Metadata>(&ctor_ref);
        let mint_ref = fungible_asset::generate_mint_ref(&ctor_ref);
        let customer_store = primary_fungible_store::ensure_primary_store_exists(
            signer::address_of(customer),
            metadata
        );

        primary_fungible_store::transfer(customer, metadata, @dutch_auction_address, 20);

        fungible_asset::mint_to(&mint_ref, customer_store, 50);

        metadata
    }
}
