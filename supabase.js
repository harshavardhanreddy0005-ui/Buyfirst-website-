/* Buyfirst Supabase client configuration.
 * This file is public. Only use a Supabase publishable key here.
 * Never add a secret/service-role key to this file.
 */
(function () {
  'use strict';
  const SUPABASE_URL = 'https://tnghetxuxxbfrhdfcugy.supabase.co';
  const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_XAjFPcnRwFQ76u53tS0fXw_cYY4CtU9';

  if (!window.supabase || typeof window.supabase.createClient !== 'function') {
    console.error('Supabase JS v2 did not load. Check the CDN script.');
    return;
  }

  const client = window.supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
    auth: {
      autoRefreshToken: true,
      persistSession: true,
      detectSessionInUrl: true
    }
  });

  const fail = (error) => { if (error) throw error; };
  const api = {
    client,

    async session() {
      const { data, error } = await client.auth.getSession();
      fail(error);
      return data.session;
    },

    async signUp({ email, password, name, phone }) {
      const { data, error } = await client.auth.signUp({
        email, password,
        options: { data: { full_name: name, phone } }
      });
      fail(error);
      return data;
    },

    async signIn(email, password) {
      const { data, error } = await client.auth.signInWithPassword({ email, password });
      fail(error);
      return data;
    },

    async signOut() {
      const { error } = await client.auth.signOut();
      fail(error);
    },

    async profile() {
      const { data: { user }, error: userError } = await client.auth.getUser();
      fail(userError);
      if (!user) return null;
      const { data, error } = await client.from('profiles')
        .select('id, full_name, phone, role, created_at')
        .eq('id', user.id).single();
      fail(error);
      return { ...data, email: user.email };
    },

    async products({ includeHidden = false } = {}) {
      let query = client.from('products').select('*').order('created_at', { ascending: false });
      if (!includeHidden) query = query.eq('is_active', true);
      const { data, error } = await query;
      fail(error);
      return data || [];
    },

    async saveProduct(product) {
      const payload = {
        title: product.title,
        description: product.description || '',
        category: product.category || 'General',
        image_url: product.image_url || null,
        images: product.images || [],
        cost_price: Number(product.cost_price || 0),
        selling_price: Number(product.selling_price),
        mrp: Number(product.mrp || product.selling_price),
        stock: Number(product.stock || 0),
        dispatch_days: Number(product.dispatch_days || 3),
        tags: product.tags || [],
        variants: product.variants || [],
        is_digital: Boolean(product.is_digital),
        digital_file_path: product.digital_file_path || null,
        is_active: product.is_active !== false,
        sku: product.sku || null
      };
      const request = product.id
        ? client.from('products').update(payload).eq('id', product.id).select().single()
        : client.from('products').insert(payload).select().single();
      const { data, error } = await request;
      fail(error);
      return data;
    },

    async deleteProduct(id) {
      const { error } = await client.from('products').delete().eq('id', id);
      fail(error);
    },

    async createOrder({ customerName, phone, address, city, state, pincode, paymentMethod, utr, items }) {
      const { data, error } = await client.rpc('create_customer_order', {
        p_customer_name: customerName,
        p_phone: phone,
        p_address: address || '',
        p_city: city || '',
        p_state: state || '',
        p_pincode: pincode || '',
        p_payment_method: paymentMethod,
        p_utr: utr || null,
        p_items: items
      });
      fail(error);
      return data;
    },

    async myOrders() {
      const { data, error } = await client.from('orders')
        .select('*, order_items(*)')
        .order('created_at', { ascending: false });
      fail(error);
      return data || [];
    },

    async submitEnquiry({ name, email, phone, message }) {
      const { data, error } = await client.from('enquiries')
        .insert({ name, email, phone: phone || null, message })
        .select().single();
      fail(error);
      return data;
    },

    async enquiries() {
      const { data, error } = await client.from('enquiries')
        .select('*').order('created_at', { ascending: false });
      fail(error);
      return data || [];
    },

    async updateOrderStatus(orderId, status) {
      const { data, error } = await client.from('orders')
        .update({ status }).eq('id', orderId).select().single();
      fail(error);
      return data;
    },

    async verifyOrderPayment(orderId, paymentStatus) {
      if (!['paid', 'rejected', 'pending'].includes(paymentStatus)) {
        throw new Error('Invalid payment status');
      }
      const { data, error } = await client.from('orders')
        .update({ payment_status: paymentStatus }).eq('id', orderId).select().single();
      fail(error);
      return data;
    },

    async uploadProductImage(file) {
      const ext = (file.name.split('.').pop() || 'bin').toLowerCase();
      const path = crypto.randomUUID() + '.' + ext;
      const { data, error } = await client.storage.from('product-images')
        .upload(path, file, { upsert: false, contentType: file.type || undefined });
      fail(error);
      const { data: publicData } = client.storage.from('product-images').getPublicUrl(data.path);
      return { path: data.path, url: publicData.publicUrl };
    },

    async uploadDigitalFile(productId, file) {
      const ext = (file.name.split('.').pop() || 'bin').toLowerCase();
      const path = String(productId) + '/' + crypto.randomUUID() + '.' + ext;
      const { data, error } = await client.storage.from('digital-files')
        .upload(path, file, { upsert: false, contentType: file.type || undefined });
      fail(error);
      return data.path;
    },

    async purchasedDownload(path) {
      const { data, error } = await client.storage.from('digital-files')
        .createSignedUrl(path, 60);
      fail(error);
      return data.signedUrl;
    },

    async isAdmin() {
      const p = await this.profile();
      return Boolean(p && p.role === 'admin');
    }
  };

  window.BuyfirstSupabase = api;
  window.dispatchEvent(new CustomEvent('buyfirst:supabase-ready', { detail: api }));
})();
