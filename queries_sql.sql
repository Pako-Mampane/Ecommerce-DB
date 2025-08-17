-- Join query
select o.orderid,
       o.orderdate,
       o.status as order_status,
       c.name as customer_name,
       c.address.city as customer_city,
       p.transactionstatus as payment_status,
       s.trackingno,
       s.deliverystatus as shipping_status,
       s.address.city as shipping_city
  from orders o
 inner join customers c
on o.customerid = ref(c)
  left join payments p
on o.payment.paymentid = p.paymentid
  left join shippings s
on o.shipping = ref(s)
 where c.address.district = 'SE'
 order by o.orderdate desc;

-- This query retrieves order details along with customer, payment, and shipping information
-- for customers located in the 'MA' district, ordered by the order date in descending order.

-- Union query
-- This query fetches all active users (customers and sellers) in Gaborone and Francistown
select c.customerid as id,
       c.name,
       c.email,
       c.contact,
       'Customer' as user_type,
       c.address.city as city
  from customers c
 where c.address.city in ( 'Gaborone',
                           'Francistown' )
   and c.role = 'customer'
union
select s.sellerid as id,
       s.name,
       s.email,
       s.contact,
       'Seller' as user_type,
       s.address.city as city
  from sellers s
 where s.address.city in ( 'Gaborone',
                           'Francistown' )
   and s.role = 'seller'
 order by city,
          name;

-- Inheritance Query 
-- This query displays product details with nested product category information
select p.productid,
       p.productname,
       p.price,
       p.status,
       p.category.categoryname as category,
       p.category.description as category_description
  from products p
 where p.status = 'available'
   and p.category.categoryname in ( 'Electronics',
                                    'Appliances' )
 order by p.category.categoryname,
          p.productname;


-- Temporal Query
-- Query provides average processing time for orders in the last 6 months
-- where the payment status is 'pending', grouped by product category and customer name
select deref(o.product).category.categoryname as category,
       deref(o.customerid).name as customer_name,
       extract(month from cast(o.orderdate as timestamp)) as order_month,
       count(o.orderid) as order_count,
       avg(extract(day from(cast(deref(o.shipping).updated_at as timestamp) - cast(o.orderdate as timestamp))) + extract(hour
       from(cast(deref(o.shipping).updated_at as timestamp) - cast(o.orderdate as timestamp))) / 24.0 + extract(minute from(cast
       (deref(o.shipping).updated_at as timestamp) - cast(o.orderdate as timestamp))) /(24.0 * 60.0) + extract(second from(cast
       (deref(o.shipping).updated_at as timestamp) - cast(o.orderdate as timestamp))) /(24.0 * 60.0 * 60.0)) as avg_processing_days
  from orders o
 where o.payment.transactionstatus = 'pending'
   and o.orderdate >= sysdate - interval '6' month
 group by deref(o.product).category.categoryname,
          deref(o.customerid).name,
          extract(month from cast(o.orderdate as timestamp))
having count(o.orderid) > 0
 order by category,
          customer_name,
          order_month;
/

-- OLAP Query
-- This query analyses sales by product category and status with rollup
select p.category.categoryname as category,
       o.status as order_status,
       count(o.orderid) as order_count,
       sum(to_number(p.price)) as total_revenue,
       grouping(p.category.categoryname) as category_grouping,
       grouping(o.status) as status_grouping
  from orders o
  join products p
on p.productid = deref(o.product).productid
 where o.payment.transactionstatus = 'completed'
 group by rollup(p.category.categoryname,
                 o.status)
having grouping_id(p.category.categoryname,
                   o.status) in ( 0,
                                  3 )
 order by p.category.categoryname,
          o.status;