SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: hstore; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS hstore WITH SCHEMA public;


--
-- Name: EXTENSION hstore; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION hstore IS 'data type for storing sets of (key, value) pairs';


--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;


--
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_stat_statements IS 'track execution statistics of all SQL statements executed';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.actions (
    id bigint NOT NULL,
    user_id bigint,
    query text,
    actions text[] DEFAULT '{}'::text[],
    feed_ids text[] DEFAULT '{}'::text[],
    all_feeds boolean DEFAULT false,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    title text,
    tag_ids bigint[] DEFAULT '{}'::bigint[],
    action_type bigint DEFAULT 0,
    computed_feed_ids bigint[] DEFAULT '{}'::bigint[],
    status bigint DEFAULT 0
);


--
-- Name: actions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.actions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: actions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.actions_id_seq OWNED BY public.actions.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: authentication_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.authentication_tokens (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    token text NOT NULL,
    purpose integer NOT NULL,
    data jsonb DEFAULT '{}'::jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    active boolean DEFAULT true NOT NULL
);


--
-- Name: authentication_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.authentication_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: authentication_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.authentication_tokens_id_seq OWNED BY public.authentication_tokens.id;


--
-- Name: billing_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billing_events (
    id bigint NOT NULL,
    details text,
    event_type character varying(255),
    billable_id bigint,
    billable_type character varying(255),
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    event_id character varying(255),
    info json
);


--
-- Name: billing_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.billing_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: billing_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.billing_events_id_seq OWNED BY public.billing_events.id;


--
-- Name: coupons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.coupons (
    id bigint NOT NULL,
    user_id bigint,
    coupon_code character varying(255),
    sent_to character varying(255),
    redeemed boolean DEFAULT false,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: coupons_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.coupons_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: coupons_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.coupons_id_seq OWNED BY public.coupons.id;


--
-- Name: deleted_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deleted_users (
    id bigint NOT NULL,
    email text,
    customer_id text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: deleted_users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.deleted_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: deleted_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.deleted_users_id_seq OWNED BY public.deleted_users.id;


--
-- Name: devices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.devices (
    id bigint NOT NULL,
    user_id bigint,
    token text,
    model text,
    device_type bigint,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    application text,
    operating_system text
);


--
-- Name: devices_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.devices_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: devices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.devices_id_seq OWNED BY public.devices.id;


--
-- Name: embeds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.embeds (
    id bigint NOT NULL,
    provider_id text NOT NULL,
    parent_id text,
    source integer NOT NULL,
    data jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: embeds_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.embeds_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: embeds_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.embeds_id_seq OWNED BY public.embeds.id;


--
-- Name: entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.entries (
    id bigint NOT NULL,
    feed_id bigint,
    title text,
    url text,
    author text,
    summary text,
    content text,
    published timestamp without time zone,
    updated timestamp without time zone,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    entry_id text,
    public_id character varying(255),
    old_public_id character varying(255),
    starred_entries_count bigint DEFAULT 0 NOT NULL,
    data json,
    original json,
    source text,
    image_url text,
    processed_image_url text,
    image json,
    recently_played_entries_count bigint DEFAULT 0,
    thread_id bigint,
    settings jsonb,
    main_tweet_id text
);


--
-- Name: entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.entries_id_seq OWNED BY public.entries.id;


--
-- Name: favicons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.favicons (
    id bigint NOT NULL,
    host text,
    favicon text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    data json,
    url character varying
);


--
-- Name: favicons_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.favicons_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: favicons_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.favicons_id_seq OWNED BY public.favicons.id;


--
-- Name: feed_stats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.feed_stats (
    id bigint NOT NULL,
    feed_id bigint,
    day date,
    entries_count bigint DEFAULT 0,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: feed_stats_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.feed_stats_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: feed_stats_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.feed_stats_id_seq OWNED BY public.feed_stats.id;


--
-- Name: feeds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.feeds (
    id bigint NOT NULL,
    title text,
    feed_url text,
    site_url text,
    etag text,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    last_modified timestamp without time zone,
    subscriptions_count bigint DEFAULT 0 NOT NULL,
    protected boolean DEFAULT false,
    push_expiration timestamp without time zone,
    last_published_entry timestamp without time zone,
    host text,
    self_url text,
    feed_type bigint DEFAULT 0,
    active boolean DEFAULT true,
    options json,
    hubs text[],
    settings jsonb
);


--
-- Name: feeds_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.feeds_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: feeds_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.feeds_id_seq OWNED BY public.feeds.id;


--
-- Name: import_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.import_items (
    id bigint NOT NULL,
    import_id bigint,
    details text,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    item_type character varying(255),
    status bigint DEFAULT 0 NOT NULL
);


--
-- Name: import_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.import_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: import_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.import_items_id_seq OWNED BY public.import_items.id;


--
-- Name: imports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.imports (
    id bigint NOT NULL,
    user_id bigint,
    complete boolean DEFAULT false,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    upload character varying(255)
);


--
-- Name: imports_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.imports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: imports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.imports_id_seq OWNED BY public.imports.id;


--
-- Name: in_app_purchases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.in_app_purchases (
    id bigint NOT NULL,
    user_id bigint,
    transaction_id text,
    purchase_date timestamp without time zone,
    receipt json,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    response json
);


--
-- Name: in_app_purchases_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.in_app_purchases_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: in_app_purchases_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.in_app_purchases_id_seq OWNED BY public.in_app_purchases.id;


--
-- Name: newsletter_senders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.newsletter_senders (
    id bigint NOT NULL,
    feed_id bigint NOT NULL,
    active boolean DEFAULT true NOT NULL,
    token text NOT NULL,
    full_token text NOT NULL,
    email text NOT NULL,
    name text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: newsletter_senders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.newsletter_senders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: newsletter_senders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.newsletter_senders_id_seq OWNED BY public.newsletter_senders.id;


--
-- Name: plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plans (
    id bigint NOT NULL,
    stripe_id character varying(255),
    name character varying(255),
    price numeric,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    price_tier bigint
);


--
-- Name: plans_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.plans_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: plans_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.plans_id_seq OWNED BY public.plans.id;


--
-- Name: recently_played_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recently_played_entries (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    entry_id bigint NOT NULL,
    progress bigint DEFAULT 0 NOT NULL,
    duration bigint DEFAULT 0 NOT NULL,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: recently_played_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.recently_played_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: recently_played_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.recently_played_entries_id_seq OWNED BY public.recently_played_entries.id;


--
-- Name: recently_read_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recently_read_entries (
    id bigint NOT NULL,
    user_id bigint,
    entry_id bigint,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: recently_read_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.recently_read_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: recently_read_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.recently_read_entries_id_seq OWNED BY public.recently_read_entries.id;


--
-- Name: saved_searches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.saved_searches (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    name text NOT NULL,
    query text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: saved_searches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.saved_searches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: saved_searches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.saved_searches_id_seq OWNED BY public.saved_searches.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying(255) NOT NULL
);


--
-- Name: sharing_services; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sharing_services (
    id bigint NOT NULL,
    user_id bigint,
    label text,
    url text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: sharing_services_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sharing_services_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sharing_services_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sharing_services_id_seq OWNED BY public.sharing_services.id;


--
-- Name: starred_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.starred_entries (
    id bigint NOT NULL,
    user_id bigint,
    feed_id bigint,
    entry_id bigint,
    published timestamp without time zone,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    source text
);


--
-- Name: starred_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.starred_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: starred_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.starred_entries_id_seq OWNED BY public.starred_entries.id;


--
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscriptions (
    id bigint NOT NULL,
    user_id bigint,
    feed_id bigint,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    title text,
    view_inline boolean DEFAULT false,
    active boolean DEFAULT true,
    push boolean DEFAULT false,
    show_updates boolean DEFAULT true,
    muted boolean DEFAULT false,
    show_retweets boolean DEFAULT true,
    media_only boolean DEFAULT false,
    kind bigint DEFAULT 0,
    view_mode bigint DEFAULT 0
);


--
-- Name: subscriptions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.subscriptions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subscriptions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.subscriptions_id_seq OWNED BY public.subscriptions.id;


--
-- Name: suggested_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.suggested_categories (
    id bigint NOT NULL,
    name text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: suggested_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.suggested_categories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: suggested_categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.suggested_categories_id_seq OWNED BY public.suggested_categories.id;


--
-- Name: suggested_feeds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.suggested_feeds (
    id bigint NOT NULL,
    suggested_category_id bigint,
    feed_id bigint,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: suggested_feeds_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.suggested_feeds_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: suggested_feeds_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.suggested_feeds_id_seq OWNED BY public.suggested_feeds.id;


--
-- Name: supported_sharing_services; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.supported_sharing_services (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    service_id character varying(255) NOT NULL,
    settings public.hstore,
    service_options json,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: supported_sharing_services_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.supported_sharing_services_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: supported_sharing_services_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.supported_sharing_services_id_seq OWNED BY public.supported_sharing_services.id;


--
-- Name: taggings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.taggings (
    id bigint NOT NULL,
    feed_id bigint,
    user_id bigint,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    tag_id bigint
);


--
-- Name: taggings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.taggings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: taggings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.taggings_id_seq OWNED BY public.taggings.id;


--
-- Name: tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tags (
    id bigint NOT NULL,
    name character varying(255),
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: tags_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tags_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tags_id_seq OWNED BY public.tags.id;


--
-- Name: twitter_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.twitter_users (
    id bigint NOT NULL,
    screen_name text NOT NULL,
    data jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: twitter_users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.twitter_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: twitter_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.twitter_users_id_seq OWNED BY public.twitter_users.id;


--
-- Name: unreads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.unreads (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    feed_id bigint NOT NULL,
    entry_id bigint NOT NULL,
    published timestamp without time zone NOT NULL,
    entry_created_at timestamp without time zone NOT NULL,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: unreads_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.unreads_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: unreads_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.unreads_id_seq OWNED BY public.unreads.id;


--
-- Name: updated_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.updated_entries (
    id bigint NOT NULL,
    user_id bigint,
    entry_id bigint,
    feed_id bigint,
    published timestamp without time zone,
    updated timestamp without time zone,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: updated_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.updated_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: updated_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.updated_entries_id_seq OWNED BY public.updated_entries.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    email character varying(255),
    password_digest character varying(255),
    customer_id character varying(255),
    last_4_digits character varying(255),
    plan_id bigint,
    admin boolean DEFAULT false,
    suspended boolean DEFAULT false,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    auth_token character varying(255),
    password_reset_token character varying(255),
    password_reset_sent_at timestamp without time zone,
    settings public.hstore,
    starred_token character varying(255),
    inbound_email_token character varying(255),
    tag_visibility json DEFAULT '{}'::json,
    expires_at timestamp without time zone,
    newsletter_token character varying,
    price_tier bigint,
    page_token character varying,
    twitter_auth_failures bigint
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: actions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actions ALTER COLUMN id SET DEFAULT nextval('public.actions_id_seq'::regclass);


--
-- Name: authentication_tokens id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.authentication_tokens ALTER COLUMN id SET DEFAULT nextval('public.authentication_tokens_id_seq'::regclass);


--
-- Name: billing_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_events ALTER COLUMN id SET DEFAULT nextval('public.billing_events_id_seq'::regclass);


--
-- Name: coupons id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coupons ALTER COLUMN id SET DEFAULT nextval('public.coupons_id_seq'::regclass);


--
-- Name: deleted_users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deleted_users ALTER COLUMN id SET DEFAULT nextval('public.deleted_users_id_seq'::regclass);


--
-- Name: devices id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices ALTER COLUMN id SET DEFAULT nextval('public.devices_id_seq'::regclass);


--
-- Name: embeds id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.embeds ALTER COLUMN id SET DEFAULT nextval('public.embeds_id_seq'::regclass);


--
-- Name: entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entries ALTER COLUMN id SET DEFAULT nextval('public.entries_id_seq'::regclass);


--
-- Name: favicons id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favicons ALTER COLUMN id SET DEFAULT nextval('public.favicons_id_seq'::regclass);


--
-- Name: feed_stats id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feed_stats ALTER COLUMN id SET DEFAULT nextval('public.feed_stats_id_seq'::regclass);


--
-- Name: feeds id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feeds ALTER COLUMN id SET DEFAULT nextval('public.feeds_id_seq'::regclass);


--
-- Name: import_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_items ALTER COLUMN id SET DEFAULT nextval('public.import_items_id_seq'::regclass);


--
-- Name: imports id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.imports ALTER COLUMN id SET DEFAULT nextval('public.imports_id_seq'::regclass);


--
-- Name: in_app_purchases id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.in_app_purchases ALTER COLUMN id SET DEFAULT nextval('public.in_app_purchases_id_seq'::regclass);


--
-- Name: newsletter_senders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.newsletter_senders ALTER COLUMN id SET DEFAULT nextval('public.newsletter_senders_id_seq'::regclass);


--
-- Name: plans id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plans ALTER COLUMN id SET DEFAULT nextval('public.plans_id_seq'::regclass);


--
-- Name: recently_played_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recently_played_entries ALTER COLUMN id SET DEFAULT nextval('public.recently_played_entries_id_seq'::regclass);


--
-- Name: recently_read_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recently_read_entries ALTER COLUMN id SET DEFAULT nextval('public.recently_read_entries_id_seq'::regclass);


--
-- Name: saved_searches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_searches ALTER COLUMN id SET DEFAULT nextval('public.saved_searches_id_seq'::regclass);


--
-- Name: sharing_services id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sharing_services ALTER COLUMN id SET DEFAULT nextval('public.sharing_services_id_seq'::regclass);


--
-- Name: starred_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.starred_entries ALTER COLUMN id SET DEFAULT nextval('public.starred_entries_id_seq'::regclass);


--
-- Name: subscriptions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions ALTER COLUMN id SET DEFAULT nextval('public.subscriptions_id_seq'::regclass);


--
-- Name: suggested_categories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suggested_categories ALTER COLUMN id SET DEFAULT nextval('public.suggested_categories_id_seq'::regclass);


--
-- Name: suggested_feeds id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suggested_feeds ALTER COLUMN id SET DEFAULT nextval('public.suggested_feeds_id_seq'::regclass);


--
-- Name: supported_sharing_services id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supported_sharing_services ALTER COLUMN id SET DEFAULT nextval('public.supported_sharing_services_id_seq'::regclass);


--
-- Name: taggings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taggings ALTER COLUMN id SET DEFAULT nextval('public.taggings_id_seq'::regclass);


--
-- Name: tags id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags ALTER COLUMN id SET DEFAULT nextval('public.tags_id_seq'::regclass);


--
-- Name: twitter_users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.twitter_users ALTER COLUMN id SET DEFAULT nextval('public.twitter_users_id_seq'::regclass);


--
-- Name: unreads id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unreads ALTER COLUMN id SET DEFAULT nextval('public.unreads_id_seq'::regclass);


--
-- Name: updated_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.updated_entries ALTER COLUMN id SET DEFAULT nextval('public.updated_entries_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: actions actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.actions
    ADD CONSTRAINT actions_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: authentication_tokens authentication_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.authentication_tokens
    ADD CONSTRAINT authentication_tokens_pkey PRIMARY KEY (id);


--
-- Name: billing_events billing_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_events
    ADD CONSTRAINT billing_events_pkey PRIMARY KEY (id);


--
-- Name: coupons coupons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coupons
    ADD CONSTRAINT coupons_pkey PRIMARY KEY (id);


--
-- Name: deleted_users deleted_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deleted_users
    ADD CONSTRAINT deleted_users_pkey PRIMARY KEY (id);


--
-- Name: devices devices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT devices_pkey PRIMARY KEY (id);


--
-- Name: embeds embeds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.embeds
    ADD CONSTRAINT embeds_pkey PRIMARY KEY (id);


--
-- Name: entries entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.entries
    ADD CONSTRAINT entries_pkey PRIMARY KEY (id);


--
-- Name: favicons favicons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.favicons
    ADD CONSTRAINT favicons_pkey PRIMARY KEY (id);


--
-- Name: feed_stats feed_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feed_stats
    ADD CONSTRAINT feed_stats_pkey PRIMARY KEY (id);


--
-- Name: feeds feeds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feeds
    ADD CONSTRAINT feeds_pkey PRIMARY KEY (id);


--
-- Name: import_items import_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_items
    ADD CONSTRAINT import_items_pkey PRIMARY KEY (id);


--
-- Name: imports imports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.imports
    ADD CONSTRAINT imports_pkey PRIMARY KEY (id);


--
-- Name: in_app_purchases in_app_purchases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.in_app_purchases
    ADD CONSTRAINT in_app_purchases_pkey PRIMARY KEY (id);


--
-- Name: newsletter_senders newsletter_senders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.newsletter_senders
    ADD CONSTRAINT newsletter_senders_pkey PRIMARY KEY (id);


--
-- Name: plans plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT plans_pkey PRIMARY KEY (id);


--
-- Name: recently_played_entries recently_played_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recently_played_entries
    ADD CONSTRAINT recently_played_entries_pkey PRIMARY KEY (id);


--
-- Name: recently_read_entries recently_read_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recently_read_entries
    ADD CONSTRAINT recently_read_entries_pkey PRIMARY KEY (id);


--
-- Name: saved_searches saved_searches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_searches
    ADD CONSTRAINT saved_searches_pkey PRIMARY KEY (id);


--
-- Name: sharing_services sharing_services_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sharing_services
    ADD CONSTRAINT sharing_services_pkey PRIMARY KEY (id);


--
-- Name: starred_entries starred_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.starred_entries
    ADD CONSTRAINT starred_entries_pkey PRIMARY KEY (id);


--
-- Name: subscriptions subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);


--
-- Name: suggested_categories suggested_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suggested_categories
    ADD CONSTRAINT suggested_categories_pkey PRIMARY KEY (id);


--
-- Name: suggested_feeds suggested_feeds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.suggested_feeds
    ADD CONSTRAINT suggested_feeds_pkey PRIMARY KEY (id);


--
-- Name: supported_sharing_services supported_sharing_services_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supported_sharing_services
    ADD CONSTRAINT supported_sharing_services_pkey PRIMARY KEY (id);


--
-- Name: taggings taggings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taggings
    ADD CONSTRAINT taggings_pkey PRIMARY KEY (id);


--
-- Name: tags tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT tags_pkey PRIMARY KEY (id);


--
-- Name: twitter_users twitter_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.twitter_users
    ADD CONSTRAINT twitter_users_pkey PRIMARY KEY (id);


--
-- Name: unreads unreads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unreads
    ADD CONSTRAINT unreads_pkey PRIMARY KEY (id);


--
-- Name: updated_entries updated_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.updated_entries
    ADD CONSTRAINT updated_entries_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: index_actions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_actions_on_user_id ON public.actions USING btree (user_id);


--
-- Name: index_authentication_tokens_on_purpose_and_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_authentication_tokens_on_purpose_and_token ON public.authentication_tokens USING btree (purpose, token);


--
-- Name: index_authentication_tokens_on_purpose_and_token_and_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_authentication_tokens_on_purpose_and_token_and_active ON public.authentication_tokens USING btree (purpose, token, active);


--
-- Name: index_authentication_tokens_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_authentication_tokens_on_user_id ON public.authentication_tokens USING btree (user_id);


--
-- Name: index_billing_events_on_billable_id_and_billable_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_billing_events_on_billable_id_and_billable_type ON public.billing_events USING btree (billable_id, billable_type);


--
-- Name: index_billing_events_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_billing_events_on_event_id ON public.billing_events USING btree (event_id);


--
-- Name: index_coupons_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_coupons_on_user_id ON public.coupons USING btree (user_id);


--
-- Name: index_deleted_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_deleted_users_on_email ON public.deleted_users USING btree (email);


--
-- Name: index_devices_on_lower_tokens; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_devices_on_lower_tokens ON public.devices USING btree (lower(token));


--
-- Name: index_devices_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_devices_on_user_id ON public.devices USING btree (user_id);


--
-- Name: index_embeds_on_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_embeds_on_parent_id ON public.embeds USING btree (parent_id);


--
-- Name: index_embeds_on_source_and_provider_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_embeds_on_source_and_provider_id ON public.embeds USING btree (source, provider_id);


--
-- Name: index_entries_on_feed_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entries_on_feed_id ON public.entries USING btree (feed_id);


--
-- Name: index_entries_on_main_tweet_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entries_on_main_tweet_id ON public.entries USING btree (main_tweet_id) WHERE (main_tweet_id IS NOT NULL);


--
-- Name: index_entries_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_entries_on_public_id ON public.entries USING btree (public_id);


--
-- Name: index_entries_on_thread_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entries_on_thread_id ON public.entries USING btree (thread_id) WHERE (thread_id IS NOT NULL);


--
-- Name: index_favicons_on_host; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_favicons_on_host ON public.favicons USING btree (host);


--
-- Name: index_feed_stats_on_feed_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feed_stats_on_feed_id ON public.feed_stats USING btree (feed_id);


--
-- Name: index_feed_stats_on_feed_id_and_day; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feed_stats_on_feed_id_and_day ON public.feed_stats USING btree (feed_id, day);


--
-- Name: index_feeds_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feeds_on_active ON public.feeds USING btree (active);


--
-- Name: index_feeds_on_feed_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feeds_on_feed_type ON public.feeds USING btree (feed_type);


--
-- Name: index_feeds_on_feed_url; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_feeds_on_feed_url ON public.feeds USING btree (feed_url);


--
-- Name: index_feeds_on_host; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feeds_on_host ON public.feeds USING btree (host);


--
-- Name: index_feeds_on_hubs; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feeds_on_hubs ON public.feeds USING btree (hubs) WHERE (hubs IS NOT NULL);


--
-- Name: index_feeds_on_last_published_entry; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feeds_on_last_published_entry ON public.feeds USING btree (last_published_entry);


--
-- Name: index_feeds_on_push_expiration; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feeds_on_push_expiration ON public.feeds USING btree (push_expiration) WHERE (push_expiration IS NOT NULL);


--
-- Name: index_import_items_on_import_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_items_on_import_id ON public.import_items USING btree (import_id);


--
-- Name: index_import_items_on_import_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_items_on_import_id_and_status ON public.import_items USING btree (import_id, status);


--
-- Name: index_in_app_purchases_on_transaction_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_in_app_purchases_on_transaction_id ON public.in_app_purchases USING btree (transaction_id);


--
-- Name: index_in_app_purchases_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_in_app_purchases_on_user_id ON public.in_app_purchases USING btree (user_id);


--
-- Name: index_newsletter_senders_on_feed_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_newsletter_senders_on_feed_id ON public.newsletter_senders USING btree (feed_id);


--
-- Name: index_newsletter_senders_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_newsletter_senders_on_token ON public.newsletter_senders USING btree (token);


--
-- Name: index_recently_played_entries_on_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recently_played_entries_on_entry_id ON public.recently_played_entries USING btree (entry_id);


--
-- Name: index_recently_played_entries_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recently_played_entries_on_user_id ON public.recently_played_entries USING btree (user_id);


--
-- Name: index_recently_played_entries_on_user_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recently_played_entries_on_user_id_and_created_at ON public.recently_played_entries USING btree (user_id, created_at);


--
-- Name: index_recently_played_entries_on_user_id_and_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_recently_played_entries_on_user_id_and_entry_id ON public.recently_played_entries USING btree (user_id, entry_id);


--
-- Name: index_recently_read_entries_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recently_read_entries_on_created_at ON public.recently_read_entries USING btree (created_at);


--
-- Name: index_recently_read_entries_on_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recently_read_entries_on_entry_id ON public.recently_read_entries USING btree (entry_id);


--
-- Name: index_recently_read_entries_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recently_read_entries_on_user_id ON public.recently_read_entries USING btree (user_id);


--
-- Name: index_recently_read_entries_on_user_id_and_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_recently_read_entries_on_user_id_and_entry_id ON public.recently_read_entries USING btree (user_id, entry_id);


--
-- Name: index_recently_read_entries_on_user_id_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recently_read_entries_on_user_id_and_id ON public.recently_read_entries USING btree (user_id, id DESC);


--
-- Name: index_saved_searches_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_saved_searches_on_user_id ON public.saved_searches USING btree (user_id);


--
-- Name: index_sharing_services_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sharing_services_on_user_id ON public.sharing_services USING btree (user_id);


--
-- Name: index_starred_entries_on_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_starred_entries_on_entry_id ON public.starred_entries USING btree (entry_id);


--
-- Name: index_starred_entries_on_feed_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_starred_entries_on_feed_id ON public.starred_entries USING btree (feed_id);


--
-- Name: index_starred_entries_on_published; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_starred_entries_on_published ON public.starred_entries USING btree (published);


--
-- Name: index_starred_entries_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_starred_entries_on_user_id ON public.starred_entries USING btree (user_id);


--
-- Name: index_starred_entries_on_user_id_and_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_starred_entries_on_user_id_and_entry_id ON public.starred_entries USING btree (user_id, entry_id);


--
-- Name: index_subscriptions_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_created_at ON public.subscriptions USING btree (created_at);


--
-- Name: index_subscriptions_on_feed_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_feed_id ON public.subscriptions USING btree (feed_id);


--
-- Name: index_subscriptions_on_feed_id_and_active_and_muted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_feed_id_and_active_and_muted ON public.subscriptions USING btree (feed_id, active, muted);


--
-- Name: index_subscriptions_on_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_kind ON public.subscriptions USING btree (kind);


--
-- Name: index_subscriptions_on_media_only; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_media_only ON public.subscriptions USING btree (media_only);


--
-- Name: index_subscriptions_on_show_retweets; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_show_retweets ON public.subscriptions USING btree (show_retweets);


--
-- Name: index_subscriptions_on_updates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_updates ON public.subscriptions USING btree (feed_id, active, muted, show_updates);


--
-- Name: index_subscriptions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_user_id ON public.subscriptions USING btree (user_id);


--
-- Name: index_subscriptions_on_user_id_and_feed_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_subscriptions_on_user_id_and_feed_id ON public.subscriptions USING btree (user_id, feed_id);


--
-- Name: index_suggested_feeds_on_feed_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_suggested_feeds_on_feed_id ON public.suggested_feeds USING btree (feed_id);


--
-- Name: index_suggested_feeds_on_suggested_category_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_suggested_feeds_on_suggested_category_id ON public.suggested_feeds USING btree (suggested_category_id);


--
-- Name: index_supported_sharing_services_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_supported_sharing_services_on_user_id ON public.supported_sharing_services USING btree (user_id);


--
-- Name: index_supported_sharing_services_on_user_id_and_service_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_supported_sharing_services_on_user_id_and_service_id ON public.supported_sharing_services USING btree (user_id, service_id);


--
-- Name: index_taggings_on_tag_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_taggings_on_tag_id ON public.taggings USING btree (tag_id);


--
-- Name: index_taggings_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_taggings_on_user_id ON public.taggings USING btree (user_id);


--
-- Name: index_taggings_on_user_id_and_feed_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_taggings_on_user_id_and_feed_id ON public.taggings USING btree (user_id, feed_id);


--
-- Name: index_taggings_on_user_id_and_tag_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_taggings_on_user_id_and_tag_id ON public.taggings USING btree (user_id, tag_id);


--
-- Name: index_tags_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tags_on_name ON public.tags USING btree (name);


--
-- Name: index_twitter_users_on_lower_screen_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_twitter_users_on_lower_screen_name ON public.twitter_users USING btree (lower(screen_name));


--
-- Name: index_unreads_on_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_unreads_on_entry_id ON public.unreads USING btree (entry_id);


--
-- Name: index_unreads_on_feed_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_unreads_on_feed_id ON public.unreads USING btree (feed_id);


--
-- Name: index_unreads_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_unreads_on_user_id ON public.unreads USING btree (user_id);


--
-- Name: index_unreads_on_user_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_unreads_on_user_id_and_created_at ON public.unreads USING btree (user_id, created_at);


--
-- Name: index_unreads_on_user_id_and_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_unreads_on_user_id_and_entry_id ON public.unreads USING btree (user_id, entry_id);


--
-- Name: index_unreads_on_user_id_and_feed_id_and_published; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_unreads_on_user_id_and_feed_id_and_published ON public.unreads USING btree (user_id, feed_id, published);


--
-- Name: index_unreads_on_user_id_and_published; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_unreads_on_user_id_and_published ON public.unreads USING btree (user_id, published);


--
-- Name: index_updated_entries_on_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_updated_entries_on_entry_id ON public.updated_entries USING btree (entry_id);


--
-- Name: index_updated_entries_on_feed_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_updated_entries_on_feed_id ON public.updated_entries USING btree (feed_id);


--
-- Name: index_updated_entries_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_updated_entries_on_user_id ON public.updated_entries USING btree (user_id);


--
-- Name: index_updated_entries_on_user_id_and_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_updated_entries_on_user_id_and_entry_id ON public.updated_entries USING btree (user_id, entry_id);


--
-- Name: index_users_on_auth_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_auth_token ON public.users USING btree (auth_token);


--
-- Name: index_users_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_customer_id ON public.users USING btree (customer_id);


--
-- Name: index_users_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_expires_at ON public.users USING btree (expires_at);


--
-- Name: index_users_on_inbound_email_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_inbound_email_token ON public.users USING btree (inbound_email_token);


--
-- Name: index_users_on_lower_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_lower_email ON public.users USING btree (lower((email)::text));


--
-- Name: index_users_on_newsletter_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_newsletter_token ON public.users USING btree (newsletter_token);


--
-- Name: index_users_on_page_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_page_token ON public.users USING btree (page_token);


--
-- Name: index_users_on_password_reset_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_password_reset_token ON public.users USING btree (password_reset_token);


--
-- Name: index_users_on_starred_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_starred_token ON public.users USING btree (starred_token);


--
-- Name: index_users_on_twitter_auth_failures; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_twitter_auth_failures ON public.users USING btree (twitter_auth_failures);


--
-- Name: unique_schema_migrations; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX unique_schema_migrations ON public.schema_migrations USING btree (version);


--
-- Name: newsletter_senders fk_rails_1aa815fea5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.newsletter_senders
    ADD CONSTRAINT fk_rails_1aa815fea5 FOREIGN KEY (feed_id) REFERENCES public.feeds(id);


--
-- Name: unreads fk_rails_90f07702a3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unreads
    ADD CONSTRAINT fk_rails_90f07702a3 FOREIGN KEY (entry_id) REFERENCES public.entries(id) ON DELETE CASCADE;


--
-- Name: authentication_tokens fk_rails_ad331ebb27; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.authentication_tokens
    ADD CONSTRAINT fk_rails_ad331ebb27 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20121010042043'),
('20121011035904'),
('20121011035933'),
('20121012074155'),
('20121012075009'),
('20121013082327'),
('20121019045613'),
('20121019150248'),
('20121019231945'),
('20121023224542'),
('20121029015723'),
('20121106123418'),
('20121109200937'),
('20121115044716'),
('20121117212752'),
('20121117225703'),
('20121124070158'),
('20121124070242'),
('20121125043913'),
('20121125051935'),
('20121202173023'),
('20121220043916'),
('20121220044158'),
('20130101205608'),
('20130107050848'),
('20130108022157'),
('20130121161637'),
('20130121162410'),
('20130121162825'),
('20130124120921'),
('20130124141157'),
('20130124144546'),
('20130124151206'),
('20130126044222'),
('20130202145544'),
('20130203182936'),
('20130203185241'),
('20130204000143'),
('20130218220024'),
('20130218221354'),
('20130226190942'),
('20130226191831'),
('20130227065820'),
('20130228150343'),
('20130228151024'),
('20130301095638'),
('20130302033514'),
('20130326034638'),
('20130327174832'),
('20130403032020'),
('20130403032414'),
('20130403032846'),
('20130407192646'),
('20130408045541'),
('20130420122821'),
('20130420171308'),
('20130420171357'),
('20130424132435'),
('20130429063608'),
('20130429152153'),
('20130429154717'),
('20130508034554'),
('20130514072924'),
('20130515203825'),
('20130517164043'),
('20130520012402'),
('20130531231556'),
('20130616023624'),
('20130616031049'),
('20130619222820'),
('20130701042440'),
('20130709054041'),
('20130713170339'),
('20130720194025'),
('20130730090745'),
('20130731234248'),
('20130801194304'),
('20130820123435'),
('20130826053351'),
('20131011204115'),
('20131017013531'),
('20131024055750'),
('20131025172652'),
('20131101024758'),
('20131101063139'),
('20131105035905'),
('20131106060451'),
('20131201051809'),
('20131202012915'),
('20131205004751'),
('20131205095630'),
('20131228183918'),
('20131231084130'),
('20140116101303'),
('20140218235831'),
('20140223114030'),
('20140227001243'),
('20140321203637'),
('20140326173619'),
('20140416025157'),
('20140505062817'),
('20140823091357'),
('20140823094323'),
('20141022031229'),
('20141110225053'),
('20141117192421'),
('20141202203934'),
('20141208231955'),
('20141215195928'),
('20150424224723'),
('20150425060924'),
('20150520213553'),
('20150602223929'),
('20150626223113'),
('20150707202540'),
('20150713230754'),
('20150714000523'),
('20150817230441'),
('20150827230751'),
('20151011143618'),
('20151019200512'),
('20151110044837'),
('20151207224028'),
('20160126003712'),
('20160504184656'),
('20160709063934'),
('20160817165958'),
('20160822194302'),
('20161110045909'),
('20170427001830'),
('20170812121620'),
('20170816220409'),
('20180102071024'),
('20180106031725'),
('20180204093407'),
('20180607200816'),
('20180714072623'),
('20180717001048'),
('20190201020722'),
('20190220004135'),
('20190225200600'),
('20190516024925'),
('20190516210058'),
('20190710112843'),
('20190715152451'),
('20190725121939'),
('20190820134157'),
('20200102115516'),
('20200103141053'),
('20200109204853'),
('20200110142059'),
('20200113101112'),
('20200708130351'),
('20200730134217'),
('20200810160825'),
('20201230004844'),
('20210102005228'),
('20210601200027');


