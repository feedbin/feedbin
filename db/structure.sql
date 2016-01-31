--
-- PostgreSQL database dump
--

-- Dumped from database version 9.5.0
-- Dumped by pg_dump version 9.5.0

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


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


SET search_path = public, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE actions (
    id integer NOT NULL,
    user_id integer,
    query text,
    actions text[] DEFAULT '{}'::text[],
    feed_ids text[] DEFAULT '{}'::text[],
    all_feeds boolean DEFAULT false,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    title text,
    tag_ids integer[] DEFAULT '{}'::integer[],
    action_type integer DEFAULT 0,
    computed_feed_ids integer[] DEFAULT '{}'::integer[]
);


--
-- Name: actions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE actions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: actions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE actions_id_seq OWNED BY actions.id;


--
-- Name: billing_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE billing_events (
    id integer NOT NULL,
    details text,
    event_type character varying(255),
    billable_id integer,
    billable_type character varying(255),
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    event_id character varying(255)
);


--
-- Name: billing_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE billing_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: billing_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE billing_events_id_seq OWNED BY billing_events.id;


--
-- Name: coupons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE coupons (
    id integer NOT NULL,
    user_id integer,
    coupon_code character varying(255),
    sent_to character varying(255),
    redeemed boolean DEFAULT false,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: coupons_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE coupons_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: coupons_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE coupons_id_seq OWNED BY coupons.id;


--
-- Name: deleted_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE deleted_users (
    id integer NOT NULL,
    email text,
    customer_id text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: deleted_users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE deleted_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: deleted_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE deleted_users_id_seq OWNED BY deleted_users.id;


--
-- Name: devices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE devices (
    id integer NOT NULL,
    user_id integer,
    token text,
    model text,
    device_type integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    application text,
    operating_system text
);


--
-- Name: devices_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE devices_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: devices_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE devices_id_seq OWNED BY devices.id;


--
-- Name: entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE entries (
    id integer NOT NULL,
    feed_id integer,
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
    starred_entries_count integer DEFAULT 0 NOT NULL,
    data json,
    original json,
    source text,
    image_url text,
    processed_image_url text,
    image json
);


--
-- Name: entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE entries_id_seq OWNED BY entries.id;


--
-- Name: favicons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE favicons (
    id integer NOT NULL,
    host text,
    favicon text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: favicons_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE favicons_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: favicons_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE favicons_id_seq OWNED BY favicons.id;


--
-- Name: feed_stats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE feed_stats (
    id integer NOT NULL,
    feed_id integer,
    day date,
    entries_count integer DEFAULT 0,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: feed_stats_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE feed_stats_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: feed_stats_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE feed_stats_id_seq OWNED BY feed_stats.id;


--
-- Name: feeds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE feeds (
    id integer NOT NULL,
    title text,
    feed_url text,
    site_url text,
    etag text,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    last_modified timestamp without time zone,
    subscriptions_count integer DEFAULT 0 NOT NULL,
    protected boolean DEFAULT false,
    push_expiration timestamp without time zone,
    last_published_entry timestamp without time zone,
    host text,
    self_url text,
    feed_type integer DEFAULT 0
);


--
-- Name: feeds_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE feeds_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: feeds_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE feeds_id_seq OWNED BY feeds.id;


--
-- Name: import_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE import_items (
    id integer NOT NULL,
    import_id integer,
    details text,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    item_type character varying(255)
);


--
-- Name: import_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE import_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: import_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE import_items_id_seq OWNED BY import_items.id;


--
-- Name: imports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE imports (
    id integer NOT NULL,
    user_id integer,
    complete boolean DEFAULT false,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    upload character varying(255)
);


--
-- Name: imports_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE imports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: imports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE imports_id_seq OWNED BY imports.id;


--
-- Name: in_app_purchases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE in_app_purchases (
    id integer NOT NULL,
    user_id integer,
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

CREATE SEQUENCE in_app_purchases_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: in_app_purchases_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE in_app_purchases_id_seq OWNED BY in_app_purchases.id;


--
-- Name: oauth_access_grants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE oauth_access_grants (
    id integer NOT NULL,
    resource_owner_id integer NOT NULL,
    application_id integer NOT NULL,
    token character varying NOT NULL,
    expires_in integer NOT NULL,
    redirect_uri text NOT NULL,
    created_at timestamp without time zone NOT NULL,
    revoked_at timestamp without time zone,
    scopes character varying
);


--
-- Name: oauth_access_grants_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE oauth_access_grants_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth_access_grants_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE oauth_access_grants_id_seq OWNED BY oauth_access_grants.id;


--
-- Name: oauth_access_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE oauth_access_tokens (
    id integer NOT NULL,
    resource_owner_id integer,
    application_id integer,
    token character varying NOT NULL,
    refresh_token character varying,
    expires_in integer,
    revoked_at timestamp without time zone,
    created_at timestamp without time zone NOT NULL,
    scopes character varying
);


--
-- Name: oauth_access_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE oauth_access_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth_access_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE oauth_access_tokens_id_seq OWNED BY oauth_access_tokens.id;


--
-- Name: oauth_applications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE oauth_applications (
    id integer NOT NULL,
    name character varying NOT NULL,
    uid character varying NOT NULL,
    secret character varying NOT NULL,
    redirect_uri text NOT NULL,
    scopes character varying DEFAULT ''::character varying NOT NULL,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: oauth_applications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE oauth_applications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: oauth_applications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE oauth_applications_id_seq OWNED BY oauth_applications.id;


--
-- Name: plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE plans (
    id integer NOT NULL,
    stripe_id character varying(255),
    name character varying(255),
    price numeric,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    price_tier integer
);


--
-- Name: plans_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE plans_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: plans_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE plans_id_seq OWNED BY plans.id;


--
-- Name: recently_read_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE recently_read_entries (
    id integer NOT NULL,
    user_id integer,
    entry_id integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: recently_read_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE recently_read_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: recently_read_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE recently_read_entries_id_seq OWNED BY recently_read_entries.id;


--
-- Name: saved_searches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE saved_searches (
    id integer NOT NULL,
    user_id integer NOT NULL,
    name text NOT NULL,
    query text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: saved_searches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE saved_searches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: saved_searches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE saved_searches_id_seq OWNED BY saved_searches.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE schema_migrations (
    version character varying(255) NOT NULL
);


--
-- Name: sharing_services; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE sharing_services (
    id integer NOT NULL,
    user_id integer,
    label text,
    url text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: sharing_services_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE sharing_services_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sharing_services_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE sharing_services_id_seq OWNED BY sharing_services.id;


--
-- Name: starred_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE starred_entries (
    id integer NOT NULL,
    user_id integer,
    feed_id integer,
    entry_id integer,
    published timestamp without time zone,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    source text
);


--
-- Name: starred_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE starred_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: starred_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE starred_entries_id_seq OWNED BY starred_entries.id;


--
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE subscriptions (
    id integer NOT NULL,
    user_id integer,
    feed_id integer,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    title text,
    view_inline boolean DEFAULT false,
    active boolean DEFAULT true,
    push boolean DEFAULT false,
    show_updates boolean DEFAULT true,
    muted boolean DEFAULT false
);


--
-- Name: subscriptions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE subscriptions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subscriptions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE subscriptions_id_seq OWNED BY subscriptions.id;


--
-- Name: suggested_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE suggested_categories (
    id integer NOT NULL,
    name text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: suggested_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE suggested_categories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: suggested_categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE suggested_categories_id_seq OWNED BY suggested_categories.id;


--
-- Name: suggested_feeds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE suggested_feeds (
    id integer NOT NULL,
    suggested_category_id integer,
    feed_id integer,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: suggested_feeds_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE suggested_feeds_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: suggested_feeds_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE suggested_feeds_id_seq OWNED BY suggested_feeds.id;


--
-- Name: supported_sharing_services; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE supported_sharing_services (
    id integer NOT NULL,
    user_id integer NOT NULL,
    service_id character varying(255) NOT NULL,
    settings hstore,
    service_options json,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: supported_sharing_services_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE supported_sharing_services_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: supported_sharing_services_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE supported_sharing_services_id_seq OWNED BY supported_sharing_services.id;


--
-- Name: taggings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE taggings (
    id integer NOT NULL,
    feed_id integer,
    user_id integer,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    tag_id integer
);


--
-- Name: taggings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE taggings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: taggings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE taggings_id_seq OWNED BY taggings.id;


--
-- Name: tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE tags (
    id integer NOT NULL,
    name character varying(255),
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: tags_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE tags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tags_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE tags_id_seq OWNED BY tags.id;


--
-- Name: unread_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE unread_entries (
    user_id integer,
    feed_id integer,
    entry_id integer,
    published timestamp without time zone,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    entry_created_at timestamp without time zone
);


--
-- Name: updated_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE updated_entries (
    id bigint NOT NULL,
    user_id integer,
    entry_id integer,
    feed_id integer,
    published timestamp without time zone,
    updated timestamp without time zone,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: updated_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE updated_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: updated_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE updated_entries_id_seq OWNED BY updated_entries.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE users (
    id integer NOT NULL,
    email character varying(255),
    password_digest character varying(255),
    customer_id character varying(255),
    last_4_digits character varying(255),
    plan_id integer,
    admin boolean DEFAULT false,
    suspended boolean DEFAULT false,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    auth_token character varying(255),
    password_reset_token character varying(255),
    password_reset_sent_at timestamp without time zone,
    settings hstore,
    starred_token character varying(255),
    inbound_email_token character varying(255),
    tag_visibility json DEFAULT '{}'::json,
    expires_at timestamp without time zone,
    newsletter_token character varying
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE users_id_seq OWNED BY users.id;


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY actions ALTER COLUMN id SET DEFAULT nextval('actions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY billing_events ALTER COLUMN id SET DEFAULT nextval('billing_events_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY coupons ALTER COLUMN id SET DEFAULT nextval('coupons_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY deleted_users ALTER COLUMN id SET DEFAULT nextval('deleted_users_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY devices ALTER COLUMN id SET DEFAULT nextval('devices_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY entries ALTER COLUMN id SET DEFAULT nextval('entries_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY favicons ALTER COLUMN id SET DEFAULT nextval('favicons_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY feed_stats ALTER COLUMN id SET DEFAULT nextval('feed_stats_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY feeds ALTER COLUMN id SET DEFAULT nextval('feeds_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY import_items ALTER COLUMN id SET DEFAULT nextval('import_items_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY imports ALTER COLUMN id SET DEFAULT nextval('imports_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY in_app_purchases ALTER COLUMN id SET DEFAULT nextval('in_app_purchases_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY oauth_access_grants ALTER COLUMN id SET DEFAULT nextval('oauth_access_grants_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY oauth_access_tokens ALTER COLUMN id SET DEFAULT nextval('oauth_access_tokens_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY oauth_applications ALTER COLUMN id SET DEFAULT nextval('oauth_applications_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY plans ALTER COLUMN id SET DEFAULT nextval('plans_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY recently_read_entries ALTER COLUMN id SET DEFAULT nextval('recently_read_entries_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY saved_searches ALTER COLUMN id SET DEFAULT nextval('saved_searches_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY sharing_services ALTER COLUMN id SET DEFAULT nextval('sharing_services_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY starred_entries ALTER COLUMN id SET DEFAULT nextval('starred_entries_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY subscriptions ALTER COLUMN id SET DEFAULT nextval('subscriptions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY suggested_categories ALTER COLUMN id SET DEFAULT nextval('suggested_categories_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY suggested_feeds ALTER COLUMN id SET DEFAULT nextval('suggested_feeds_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY supported_sharing_services ALTER COLUMN id SET DEFAULT nextval('supported_sharing_services_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY taggings ALTER COLUMN id SET DEFAULT nextval('taggings_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY tags ALTER COLUMN id SET DEFAULT nextval('tags_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY updated_entries ALTER COLUMN id SET DEFAULT nextval('updated_entries_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY users ALTER COLUMN id SET DEFAULT nextval('users_id_seq'::regclass);


--
-- Name: actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY actions
    ADD CONSTRAINT actions_pkey PRIMARY KEY (id);


--
-- Name: billing_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY billing_events
    ADD CONSTRAINT billing_events_pkey PRIMARY KEY (id);


--
-- Name: coupons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY coupons
    ADD CONSTRAINT coupons_pkey PRIMARY KEY (id);


--
-- Name: deleted_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY deleted_users
    ADD CONSTRAINT deleted_users_pkey PRIMARY KEY (id);


--
-- Name: devices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY devices
    ADD CONSTRAINT devices_pkey PRIMARY KEY (id);


--
-- Name: entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY entries
    ADD CONSTRAINT entries_pkey PRIMARY KEY (id);


--
-- Name: favicons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY favicons
    ADD CONSTRAINT favicons_pkey PRIMARY KEY (id);


--
-- Name: feed_stats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY feed_stats
    ADD CONSTRAINT feed_stats_pkey PRIMARY KEY (id);


--
-- Name: feeds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY feeds
    ADD CONSTRAINT feeds_pkey PRIMARY KEY (id);


--
-- Name: import_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY import_items
    ADD CONSTRAINT import_items_pkey PRIMARY KEY (id);


--
-- Name: imports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY imports
    ADD CONSTRAINT imports_pkey PRIMARY KEY (id);


--
-- Name: in_app_purchases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY in_app_purchases
    ADD CONSTRAINT in_app_purchases_pkey PRIMARY KEY (id);


--
-- Name: oauth_access_grants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY oauth_access_grants
    ADD CONSTRAINT oauth_access_grants_pkey PRIMARY KEY (id);


--
-- Name: oauth_access_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY oauth_access_tokens
    ADD CONSTRAINT oauth_access_tokens_pkey PRIMARY KEY (id);


--
-- Name: oauth_applications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY oauth_applications
    ADD CONSTRAINT oauth_applications_pkey PRIMARY KEY (id);


--
-- Name: plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY plans
    ADD CONSTRAINT plans_pkey PRIMARY KEY (id);


--
-- Name: recently_read_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY recently_read_entries
    ADD CONSTRAINT recently_read_entries_pkey PRIMARY KEY (id);


--
-- Name: saved_searches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY saved_searches
    ADD CONSTRAINT saved_searches_pkey PRIMARY KEY (id);


--
-- Name: sharing_services_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY sharing_services
    ADD CONSTRAINT sharing_services_pkey PRIMARY KEY (id);


--
-- Name: starred_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY starred_entries
    ADD CONSTRAINT starred_entries_pkey PRIMARY KEY (id);


--
-- Name: subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);


--
-- Name: suggested_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY suggested_categories
    ADD CONSTRAINT suggested_categories_pkey PRIMARY KEY (id);


--
-- Name: suggested_feeds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY suggested_feeds
    ADD CONSTRAINT suggested_feeds_pkey PRIMARY KEY (id);


--
-- Name: supported_sharing_services_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY supported_sharing_services
    ADD CONSTRAINT supported_sharing_services_pkey PRIMARY KEY (id);


--
-- Name: taggings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY taggings
    ADD CONSTRAINT taggings_pkey PRIMARY KEY (id);


--
-- Name: tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY tags
    ADD CONSTRAINT tags_pkey PRIMARY KEY (id);


--
-- Name: updated_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY updated_entries
    ADD CONSTRAINT updated_entries_pkey PRIMARY KEY (id);


--
-- Name: users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: index_actions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_actions_on_user_id ON actions USING btree (user_id);


--
-- Name: index_billing_events_on_billable_id_and_billable_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_billing_events_on_billable_id_and_billable_type ON billing_events USING btree (billable_id, billable_type);


--
-- Name: index_billing_events_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_billing_events_on_event_id ON billing_events USING btree (event_id);


--
-- Name: index_coupons_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_coupons_on_user_id ON coupons USING btree (user_id);


--
-- Name: index_deleted_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_deleted_users_on_email ON deleted_users USING btree (email);


--
-- Name: index_devices_on_lower_tokens; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_devices_on_lower_tokens ON devices USING btree (lower(token));


--
-- Name: index_devices_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_devices_on_user_id ON devices USING btree (user_id);


--
-- Name: index_entries_on_feed_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_entries_on_feed_id ON entries USING btree (feed_id);


--
-- Name: index_entries_on_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_entries_on_public_id ON entries USING btree (public_id);


--
-- Name: index_favicons_on_host; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_favicons_on_host ON favicons USING btree (host);


--
-- Name: index_feed_stats_on_feed_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feed_stats_on_feed_id ON feed_stats USING btree (feed_id);


--
-- Name: index_feed_stats_on_feed_id_and_day; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feed_stats_on_feed_id_and_day ON feed_stats USING btree (feed_id, day);


--
-- Name: index_feeds_on_feed_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feeds_on_feed_type ON feeds USING btree (feed_type);


--
-- Name: index_feeds_on_feed_url; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_feeds_on_feed_url ON feeds USING btree (feed_url);


--
-- Name: index_feeds_on_host; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feeds_on_host ON feeds USING btree (host);


--
-- Name: index_feeds_on_last_published_entry; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feeds_on_last_published_entry ON feeds USING btree (last_published_entry);


--
-- Name: index_import_items_on_import_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_items_on_import_id ON import_items USING btree (import_id);


--
-- Name: index_in_app_purchases_on_transaction_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_in_app_purchases_on_transaction_id ON in_app_purchases USING btree (transaction_id);


--
-- Name: index_in_app_purchases_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_in_app_purchases_on_user_id ON in_app_purchases USING btree (user_id);


--
-- Name: index_oauth_access_grants_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_access_grants_on_token ON oauth_access_grants USING btree (token);


--
-- Name: index_oauth_access_tokens_on_refresh_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_access_tokens_on_refresh_token ON oauth_access_tokens USING btree (refresh_token);


--
-- Name: index_oauth_access_tokens_on_resource_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_oauth_access_tokens_on_resource_owner_id ON oauth_access_tokens USING btree (resource_owner_id);


--
-- Name: index_oauth_access_tokens_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_access_tokens_on_token ON oauth_access_tokens USING btree (token);


--
-- Name: index_oauth_applications_on_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oauth_applications_on_uid ON oauth_applications USING btree (uid);


--
-- Name: index_recently_read_entries_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recently_read_entries_on_created_at ON recently_read_entries USING btree (created_at);


--
-- Name: index_recently_read_entries_on_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recently_read_entries_on_entry_id ON recently_read_entries USING btree (entry_id);


--
-- Name: index_recently_read_entries_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recently_read_entries_on_user_id ON recently_read_entries USING btree (user_id);


--
-- Name: index_recently_read_entries_on_user_id_and_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_recently_read_entries_on_user_id_and_entry_id ON recently_read_entries USING btree (user_id, entry_id);


--
-- Name: index_saved_searches_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_saved_searches_on_user_id ON saved_searches USING btree (user_id);


--
-- Name: index_sharing_services_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sharing_services_on_user_id ON sharing_services USING btree (user_id);


--
-- Name: index_starred_entries_on_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_starred_entries_on_entry_id ON starred_entries USING btree (entry_id);


--
-- Name: index_starred_entries_on_feed_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_starred_entries_on_feed_id ON starred_entries USING btree (feed_id);


--
-- Name: index_starred_entries_on_published; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_starred_entries_on_published ON starred_entries USING btree (published);


--
-- Name: index_starred_entries_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_starred_entries_on_user_id ON starred_entries USING btree (user_id);


--
-- Name: index_starred_entries_on_user_id_and_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_starred_entries_on_user_id_and_entry_id ON starred_entries USING btree (user_id, entry_id);


--
-- Name: index_subscriptions_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_created_at ON subscriptions USING btree (created_at);


--
-- Name: index_subscriptions_on_feed_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_feed_id ON subscriptions USING btree (feed_id);


--
-- Name: index_subscriptions_on_feed_id_and_active_and_muted; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_feed_id_and_active_and_muted ON subscriptions USING btree (feed_id, active, muted);


--
-- Name: index_subscriptions_on_updates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_updates ON subscriptions USING btree (feed_id, active, muted, show_updates);


--
-- Name: index_subscriptions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_user_id ON subscriptions USING btree (user_id);


--
-- Name: index_subscriptions_on_user_id_and_feed_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_subscriptions_on_user_id_and_feed_id ON subscriptions USING btree (user_id, feed_id);


--
-- Name: index_suggested_feeds_on_feed_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_suggested_feeds_on_feed_id ON suggested_feeds USING btree (feed_id);


--
-- Name: index_suggested_feeds_on_suggested_category_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_suggested_feeds_on_suggested_category_id ON suggested_feeds USING btree (suggested_category_id);


--
-- Name: index_supported_sharing_services_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_supported_sharing_services_on_user_id ON supported_sharing_services USING btree (user_id);


--
-- Name: index_supported_sharing_services_on_user_id_and_service_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_supported_sharing_services_on_user_id_and_service_id ON supported_sharing_services USING btree (user_id, service_id);


--
-- Name: index_taggings_on_tag_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_taggings_on_tag_id ON taggings USING btree (tag_id);


--
-- Name: index_taggings_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_taggings_on_user_id ON taggings USING btree (user_id);


--
-- Name: index_taggings_on_user_id_and_feed_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_taggings_on_user_id_and_feed_id ON taggings USING btree (user_id, feed_id);


--
-- Name: index_taggings_on_user_id_and_tag_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_taggings_on_user_id_and_tag_id ON taggings USING btree (user_id, tag_id);


--
-- Name: index_tags_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tags_on_name ON tags USING btree (name);


--
-- Name: index_unread_entries_on_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_unread_entries_on_entry_id ON unread_entries USING btree (entry_id);


--
-- Name: index_unread_entries_on_feed_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_unread_entries_on_feed_id ON unread_entries USING btree (feed_id);


--
-- Name: index_unread_entries_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_unread_entries_on_user_id ON unread_entries USING btree (user_id);


--
-- Name: index_unread_entries_on_user_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_unread_entries_on_user_id_and_created_at ON unread_entries USING btree (user_id, created_at);


--
-- Name: index_unread_entries_on_user_id_and_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_unread_entries_on_user_id_and_entry_id ON unread_entries USING btree (user_id, entry_id);


--
-- Name: index_unread_entries_on_user_id_and_feed_id_and_published; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_unread_entries_on_user_id_and_feed_id_and_published ON unread_entries USING btree (user_id, feed_id, published);


--
-- Name: index_unread_entries_on_user_id_and_published; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_unread_entries_on_user_id_and_published ON unread_entries USING btree (user_id, published);


--
-- Name: index_updated_entries_on_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_updated_entries_on_entry_id ON updated_entries USING btree (entry_id);


--
-- Name: index_updated_entries_on_feed_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_updated_entries_on_feed_id ON updated_entries USING btree (feed_id);


--
-- Name: index_updated_entries_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_updated_entries_on_user_id ON updated_entries USING btree (user_id);


--
-- Name: index_updated_entries_on_user_id_and_entry_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_updated_entries_on_user_id_and_entry_id ON updated_entries USING btree (user_id, entry_id);


--
-- Name: index_users_on_auth_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_auth_token ON users USING btree (auth_token);


--
-- Name: index_users_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_customer_id ON users USING btree (customer_id);


--
-- Name: index_users_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_expires_at ON users USING btree (expires_at);


--
-- Name: index_users_on_inbound_email_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_inbound_email_token ON users USING btree (inbound_email_token);


--
-- Name: index_users_on_lower_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_lower_email ON users USING btree (lower((email)::text));


--
-- Name: index_users_on_newsletter_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_newsletter_token ON users USING btree (newsletter_token);


--
-- Name: index_users_on_password_reset_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_password_reset_token ON users USING btree (password_reset_token);


--
-- Name: index_users_on_starred_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_starred_token ON users USING btree (starred_token);


--
-- Name: unique_schema_migrations; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX unique_schema_migrations ON schema_migrations USING btree (version);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO schema_migrations (version) VALUES ('20121010042043');

INSERT INTO schema_migrations (version) VALUES ('20121011035904');

INSERT INTO schema_migrations (version) VALUES ('20121011035933');

INSERT INTO schema_migrations (version) VALUES ('20121012074155');

INSERT INTO schema_migrations (version) VALUES ('20121012075009');

INSERT INTO schema_migrations (version) VALUES ('20121013082327');

INSERT INTO schema_migrations (version) VALUES ('20121019045613');

INSERT INTO schema_migrations (version) VALUES ('20121019150248');

INSERT INTO schema_migrations (version) VALUES ('20121019231945');

INSERT INTO schema_migrations (version) VALUES ('20121023224542');

INSERT INTO schema_migrations (version) VALUES ('20121029015723');

INSERT INTO schema_migrations (version) VALUES ('20121106123418');

INSERT INTO schema_migrations (version) VALUES ('20121109200937');

INSERT INTO schema_migrations (version) VALUES ('20121115044716');

INSERT INTO schema_migrations (version) VALUES ('20121117212752');

INSERT INTO schema_migrations (version) VALUES ('20121117225703');

INSERT INTO schema_migrations (version) VALUES ('20121124070158');

INSERT INTO schema_migrations (version) VALUES ('20121124070242');

INSERT INTO schema_migrations (version) VALUES ('20121125043913');

INSERT INTO schema_migrations (version) VALUES ('20121125051935');

INSERT INTO schema_migrations (version) VALUES ('20121202173023');

INSERT INTO schema_migrations (version) VALUES ('20121220043916');

INSERT INTO schema_migrations (version) VALUES ('20121220044158');

INSERT INTO schema_migrations (version) VALUES ('20130101205608');

INSERT INTO schema_migrations (version) VALUES ('20130107050848');

INSERT INTO schema_migrations (version) VALUES ('20130108022157');

INSERT INTO schema_migrations (version) VALUES ('20130121161637');

INSERT INTO schema_migrations (version) VALUES ('20130121162410');

INSERT INTO schema_migrations (version) VALUES ('20130121162825');

INSERT INTO schema_migrations (version) VALUES ('20130124120921');

INSERT INTO schema_migrations (version) VALUES ('20130124141157');

INSERT INTO schema_migrations (version) VALUES ('20130124144546');

INSERT INTO schema_migrations (version) VALUES ('20130124151206');

INSERT INTO schema_migrations (version) VALUES ('20130126044222');

INSERT INTO schema_migrations (version) VALUES ('20130202145544');

INSERT INTO schema_migrations (version) VALUES ('20130203182936');

INSERT INTO schema_migrations (version) VALUES ('20130203185241');

INSERT INTO schema_migrations (version) VALUES ('20130204000143');

INSERT INTO schema_migrations (version) VALUES ('20130218220024');

INSERT INTO schema_migrations (version) VALUES ('20130218221354');

INSERT INTO schema_migrations (version) VALUES ('20130226190942');

INSERT INTO schema_migrations (version) VALUES ('20130226191831');

INSERT INTO schema_migrations (version) VALUES ('20130227065820');

INSERT INTO schema_migrations (version) VALUES ('20130228150343');

INSERT INTO schema_migrations (version) VALUES ('20130228151024');

INSERT INTO schema_migrations (version) VALUES ('20130301095638');

INSERT INTO schema_migrations (version) VALUES ('20130302033514');

INSERT INTO schema_migrations (version) VALUES ('20130326034638');

INSERT INTO schema_migrations (version) VALUES ('20130327174832');

INSERT INTO schema_migrations (version) VALUES ('20130403032020');

INSERT INTO schema_migrations (version) VALUES ('20130403032414');

INSERT INTO schema_migrations (version) VALUES ('20130403032846');

INSERT INTO schema_migrations (version) VALUES ('20130407192646');

INSERT INTO schema_migrations (version) VALUES ('20130408045541');

INSERT INTO schema_migrations (version) VALUES ('20130420122821');

INSERT INTO schema_migrations (version) VALUES ('20130420171308');

INSERT INTO schema_migrations (version) VALUES ('20130420171357');

INSERT INTO schema_migrations (version) VALUES ('20130424132435');

INSERT INTO schema_migrations (version) VALUES ('20130429063608');

INSERT INTO schema_migrations (version) VALUES ('20130429152153');

INSERT INTO schema_migrations (version) VALUES ('20130429154717');

INSERT INTO schema_migrations (version) VALUES ('20130508034554');

INSERT INTO schema_migrations (version) VALUES ('20130514072924');

INSERT INTO schema_migrations (version) VALUES ('20130515203825');

INSERT INTO schema_migrations (version) VALUES ('20130517164043');

INSERT INTO schema_migrations (version) VALUES ('20130520012402');

INSERT INTO schema_migrations (version) VALUES ('20130531231556');

INSERT INTO schema_migrations (version) VALUES ('20130616023624');

INSERT INTO schema_migrations (version) VALUES ('20130616031049');

INSERT INTO schema_migrations (version) VALUES ('20130619222820');

INSERT INTO schema_migrations (version) VALUES ('20130701042440');

INSERT INTO schema_migrations (version) VALUES ('20130709054041');

INSERT INTO schema_migrations (version) VALUES ('20130713170339');

INSERT INTO schema_migrations (version) VALUES ('20130720194025');

INSERT INTO schema_migrations (version) VALUES ('20130730090745');

INSERT INTO schema_migrations (version) VALUES ('20130731234248');

INSERT INTO schema_migrations (version) VALUES ('20130801194304');

INSERT INTO schema_migrations (version) VALUES ('20130820123435');

INSERT INTO schema_migrations (version) VALUES ('20130826053351');

INSERT INTO schema_migrations (version) VALUES ('20131011204115');

INSERT INTO schema_migrations (version) VALUES ('20131017013531');

INSERT INTO schema_migrations (version) VALUES ('20131024055750');

INSERT INTO schema_migrations (version) VALUES ('20131025172652');

INSERT INTO schema_migrations (version) VALUES ('20131101024758');

INSERT INTO schema_migrations (version) VALUES ('20131101063139');

INSERT INTO schema_migrations (version) VALUES ('20131105035905');

INSERT INTO schema_migrations (version) VALUES ('20131106060451');

INSERT INTO schema_migrations (version) VALUES ('20131201051809');

INSERT INTO schema_migrations (version) VALUES ('20131202012915');

INSERT INTO schema_migrations (version) VALUES ('20131205004751');

INSERT INTO schema_migrations (version) VALUES ('20131205095630');

INSERT INTO schema_migrations (version) VALUES ('20131228183918');

INSERT INTO schema_migrations (version) VALUES ('20131231084130');

INSERT INTO schema_migrations (version) VALUES ('20140116101303');

INSERT INTO schema_migrations (version) VALUES ('20140218235831');

INSERT INTO schema_migrations (version) VALUES ('20140223114030');

INSERT INTO schema_migrations (version) VALUES ('20140227001243');

INSERT INTO schema_migrations (version) VALUES ('20140321203637');

INSERT INTO schema_migrations (version) VALUES ('20140326173619');

INSERT INTO schema_migrations (version) VALUES ('20140416025157');

INSERT INTO schema_migrations (version) VALUES ('20140505062817');

INSERT INTO schema_migrations (version) VALUES ('20140823091357');

INSERT INTO schema_migrations (version) VALUES ('20140823094323');

INSERT INTO schema_migrations (version) VALUES ('20141022031229');

INSERT INTO schema_migrations (version) VALUES ('20141110225053');

INSERT INTO schema_migrations (version) VALUES ('20141117192421');

INSERT INTO schema_migrations (version) VALUES ('20141202203934');

INSERT INTO schema_migrations (version) VALUES ('20141208231955');

INSERT INTO schema_migrations (version) VALUES ('20141215195928');

INSERT INTO schema_migrations (version) VALUES ('20150424224723');

INSERT INTO schema_migrations (version) VALUES ('20150425060924');

INSERT INTO schema_migrations (version) VALUES ('20150520213553');

INSERT INTO schema_migrations (version) VALUES ('20150602223929');

INSERT INTO schema_migrations (version) VALUES ('20150626223113');

INSERT INTO schema_migrations (version) VALUES ('20150707202540');

INSERT INTO schema_migrations (version) VALUES ('20150713230754');

INSERT INTO schema_migrations (version) VALUES ('20150714000523');

INSERT INTO schema_migrations (version) VALUES ('20150817230441');

INSERT INTO schema_migrations (version) VALUES ('20150827230751');

INSERT INTO schema_migrations (version) VALUES ('20151011143618');

INSERT INTO schema_migrations (version) VALUES ('20151019200512');

INSERT INTO schema_migrations (version) VALUES ('20151110044837');

INSERT INTO schema_migrations (version) VALUES ('20151207224028');

INSERT INTO schema_migrations (version) VALUES ('20160126003712');

INSERT INTO schema_migrations (version) VALUES ('20160131175812');

