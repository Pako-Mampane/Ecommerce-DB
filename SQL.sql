-- Dropping all objects in the schema if they exist

begin
   for r in (
      select object_name,
             object_type
        from user_objects
       where object_type in ( 'TABLE',
                              'VIEW',
                              'SEQUENCE',
                              'PROCEDURE',
                              'FUNCTION',
                              'PACKAGE BODY',
                              'TRIGGER',
                              'TYPE' )
   ) loop
      begin
         if r.object_type = 'TABLE' then
            execute immediate 'DROP TABLE "'
                              || r.object_name
                              || '" CASCADE CONSTRAINTS';
         elsif r.object_type = 'VIEW' then
            execute immediate 'DROP VIEW "'
                              || r.object_name
                              || '"';
         elsif r.object_type = 'SEQUENCE' then
            execute immediate 'DROP SEQUENCE "'
                              || r.object_name
                              || '"';
         elsif r.object_type in ( 'PROCEDURE',
                                  'FUNCTION' ) then
            execute immediate 'DROP '
                              || r.object_type
                              || ' "'
                              || r.object_name
                              || '"';
         elsif r.object_type = 'TRIGGER' then
            execute immediate 'DROP TRIGGER "'
                              || r.object_name
                              || '"';
         elsif r.object_type = 'TYPE' then
            execute immediate 'DROP TYPE "'
                              || r.object_name
                              || '" FORCE';
         end if;
      exception
         when others then
            dbms_output.put_line('Failed to drop '
                                 || r.object_type
                                 || ' '
                                 || r.object_name
                                 || ': '
                                 || sqlerrm);
      end;
   end loop;
end;
/

------------BASE OBJECT TYPE CREATION--------------
create type address_type as object (
      street   varchar2(100),
      city     varchar2(50),
      district varchar2(50),
      member function get_full_address return varchar2
) not final;
/
create type body address_type as
   member function get_full_address return varchar2 is
   begin
      return street
             || ', '
             || city
             || ', '
             || district;
   end;
end;
/
create type base_user_type as object (
      userid    varchar2(20),
      name      varchar2(50),
      email     varchar2(100),
      contact   varchar2(20),
      address   address_type,
      role      varchar2(20),
      joined_at date
) not final;
/
create type customer_type under base_user_type (
      customerid varchar2(20),
      user_ref   ref base_user_type
) not final;
/
create type seller_type under base_user_type (
      sellerid varchar2(20),
      user_ref ref base_user_type
) not final;
/
create type employee_type under base_user_type (
      employeeid varchar2(20),
      user_ref   ref base_user_type
) not final;
/
create type product_category_type as object (
      categoryid   varchar2(20),
      categoryname varchar2(50),
      description  varchar2(300)
) not final;
/
create type product_type as object (
      productid     varchar2(20),
      productname   varchar2(50),
      price         varchar2(10),
      category      product_category_type,
      stockquantity number,
      status        varchar2(20),
      created_at    date,
      updated_at    date,
      sellerid      ref seller_type
) not final;
/
create type payment_type as object (
      paymentid         varchar2(20),
      amount            float,
      transactionstatus varchar2(20)
) not final;
/
create type shipping_type as object (
      shippingid     varchar2(20),
      trackingno     varchar2(50),
      deliverystatus varchar2(20),
      address        address_type,
      created_at     date,
      updated_at     date
)
/
create type order_type as object (
      orderid    varchar2(20),
      orderdate  date,
      status     varchar2(20),
      customerid ref customer_type,
      payment    payment_type,
      shipping   ref shipping_type,
      product    ref product_type,
      quantity   number
)
/
create sequence order_seq start with 1 increment by 1
/
create type warehouse_type as object (
      warehouseid varchar2(20),
      location    varchar2(200),
      capacity    integer,
      employeeid  ref employee_type
)
/
----------- TABLE CREATION-------------
create table users of base_user_type (
   constraint pk_users primary key ( userid ),
   constraint chk_email check ( regexp_like ( email,
                                              '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' ) ),
   role check ( role in ( 'customer',
                          'seller',
                          'employee' ) )
);

create table customers of customer_type (
   constraint pk_customers primary key ( customerid ),
   constraint fk_user_ref_c foreign key ( userid )
      references users ( userid )
);

create table sellers of seller_type (
   constraint pk_sellers primary key ( sellerid ),
   constraint fk_user_ref_s foreign key ( userid )
      references users ( userid )
);

create table employees of employee_type (
   constraint pk_employees primary key ( employeeid ),
   constraint fk_user_ref_e foreign key ( userid )
      references users ( userid )
);

create table product_categories of product_category_type (
   constraint pk_product_categories primary key ( categoryid )
);

create table products of product_type (
   constraint pk_products primary key ( productid ),
   status check ( status in ( 'available',
                              'out of stock' ) ),
   price not null
);
create table payments of payment_type (
   constraint pk_payments primary key ( paymentid ),
   constraint chk_payment_amount check ( amount > 0 ),
   constraint chk_transaction_status
      check ( transactionstatus in ( 'pending',
                                     'completed',
                                     'failed' ) )
);

create table shippings of shipping_type (
   constraint pk_shippings primary key ( shippingid ),
   trackingno not null,
   constraint chk_deliverystatus
      check ( deliverystatus in ( 'pending',
                                  'shipped',
                                  'delivered',
                                  'returned' ) )
);

create table orders of order_type (
   constraint pk_orders primary key ( orderid ),
   status check ( status in ( 'pending',
                              'processing',
                              'shipped',
                              'delivered' ) ),
   constraint fk_customer foreign key ( customerid )
      references customers,
   constraint fk_shipping foreign key ( shipping )
      references shippings,
   constraint fk_product foreign key ( product )
      references products
);

create table warehouses of warehouse_type (
   warehouseid primary key
);

------------ Creating Triggers------------- 
create or replace trigger trigger_update_product_status before
   insert or update of status on products
   for each row
   when ( new.status not in ( 'available',
                              'out of stock' ) )
begin
   raise_application_error(
      -20001,
      'Status must be "available" or "out of stock"'
   );
end;
/
create or replace trigger trg_prevent_order_deletion before
   delete on orders
   for each row
begin
   raise_application_error(
      -20005,
      'Deletion of orders is not allowed to maintain transaction history.'
   );
end;
/
create or replace trigger trg_validate_payment_amount before
   insert on orders
   for each row
declare
   v_product_price  number(
      10,
      2
   );
   v_payment_amount float;
begin
   select to_number(p.price)
     into v_product_price
     from products p
    where p.productid = deref(:new.product).productid;

   v_payment_amount := :new.payment.amount;
   if
      v_payment_amount is not null
      and abs(v_payment_amount -(v_product_price * :new.quantity)) > 0.01
   then
      raise_application_error(
         -20006,
         'Payment amount does not match order cost.'
      );
   end if;
exception
   when no_data_found then
      raise_application_error(
         -20007,
         'Product not found for order.'
      );
   when others then
      raise;
end;
/
----------- Stored procedures----------------
create or replace procedure place_order (
   p_customerid in varchar2,
   p_productids in sys.odcivarchar2list,
   p_payment    in payment_type,
   p_shipping   in shipping_type,
   p_quantities in sys.odcinumberlist
) as
   v_orderid        varchar2(20);
   v_orderdate      date := sysdate;
   v_productprice   number(
      10,
      2
   );
   v_stockquantity  number(10);
   v_customer_ref   ref customer_type;
   v_shipping_ref   ref shipping_type;
   v_product_ref    ref product_type;
   v_payment_amount number(
      10,
      2
   );
begin
   -- Validate input arrays
   if p_productids.count != p_quantities.count then
      raise_application_error(
         -20012,
         'Number of products and quantities must match.'
      );
   end if;

   -- Generate order ID
   v_orderid := 'ORD-'
                || '-'
                || lpad(
      order_seq.nextval,
      6,
      '0'
   );
   dbms_output.put_line('Generated order ID: ' || v_orderid);

   -- Get customer reference
   dbms_output.put_line('Fetching customer ref for: ' || p_customerid);
   select ref(c)
     into v_customer_ref
     from customers c
    where c.customerid = p_customerid;

   -- Check for duplicate shipping ID
   begin
      select ref(s)
        into v_shipping_ref
        from shippings s
       where s.shippingid = p_shipping.shippingid;
      raise_application_error(
         -20013,
         'Shipping ID '
         || p_shipping.shippingid
         || ' already exists.'
      );
   exception
      when no_data_found then
         -- Insert shipping and get reference
         dbms_output.put_line('Inserting shipping: ' || p_shipping.shippingid);
         insert into shippings values ( p_shipping );
         select ref(s)
           into v_shipping_ref
           from shippings s
          where s.shippingid = p_shipping.shippingid;
   end;

   -- Process each product and create an order for each
   for i in 1..p_productids.count loop
      dbms_output.put_line('Processing product: ' || p_productids(i));
      select to_number(price),
             stockquantity,
             ref(p)
        into
         v_productprice,
         v_stockquantity,
         v_product_ref
        from products p
       where p.productid = p_productids(i);

      if v_stockquantity < p_quantities(i) then
         raise_application_error(
            -20002,
            'Insufficient stock for product ' || p_productids(i)
         );
      end if;

      -- Calculate payment amount for this product
      v_payment_amount := v_productprice * p_quantities(i);
      dbms_output.put_line('Calculated payment amount for product '
                           || p_productids(i)
                           || ': '
                           || v_payment_amount);

      -- Create order for this product with calculated payment
      insert into orders (
         orderid,
         orderdate,
         status,
         customerid,
         payment,
         shipping,
         product,
         quantity
      ) values ( v_orderid
                 || '-'
                 || i,
                 v_orderdate,
                 'pending',
                 v_customer_ref,
                 payment_type(
                    p_payment.paymentid
                    || '-'
                    || i,
                    v_payment_amount,
                    p_payment.transactionstatus
                 ),
                 v_shipping_ref,
                 v_product_ref,
                 p_quantities(i) );

      -- Update stock
      update products
         set
         stockquantity = stockquantity - p_quantities(i)
       where productid = p_productids(i);
   end loop;

   commit;
   dbms_output.put_line('Order '
                        || v_orderid
                        || ' placed successfully with '
                        || p_productids.count
                        || ' products.');
exception
   when no_data_found then
      dbms_output.put_line('No data found error at: ' || dbms_utility.format_error_backtrace);
      raise_application_error(
         -20011,
         'No data found for customer, shipping, or product.'
      );
   when others then
      dbms_output.put_line('Error: '
                           || sqlerrm
                           || ' at '
                           || dbms_utility.format_error_backtrace);
      rollback;
      raise;
end;
/
create or replace procedure add_customer (
   p_userid     in varchar2,
   p_customerid in varchar2
) as
   v_user     base_user_type;
   v_user_ref ref base_user_type;
begin
   select value(u),
          ref(u)
     into
      v_user,
      v_user_ref
     from users u
    where u.userid = p_userid;

   insert into customers values ( customer_type(
      v_user.userid,
      v_user.name,
      v_user.email,
      v_user.contact,
      v_user.address,
      v_user.role,
      v_user.joined_at,
      p_customerid,
      v_user_ref
   ) );

   commit;
   dbms_output.put_line('Customer '
                        || p_customerid
                        || ' added successfully');
end;
/
create or replace procedure add_seller (
   p_userid   in varchar2,
   p_sellerid in varchar2
) as
   v_seller   base_user_type;
   v_user_ref ref base_user_type;
begin
   select value(u)
     into v_seller
     from users u
    where u.userid = p_userid;

   insert into sellers values ( seller_type(
      v_seller.userid,
      v_seller.name,
      v_seller.email,
      v_seller.contact,
      v_seller.address,
      v_seller.role,
      v_seller.joined_at,
      p_sellerid,
      v_user_ref
   ) );
   commit;
   dbms_output.put_line('Seller '
                        || p_sellerid
                        || ' added successfully');
end;
/
create or replace procedure add_employee (
   p_userid     in varchar2,
   p_employeeid in varchar2
) as
   v_employee base_user_type;
   v_user_ref ref base_user_type;
begin
   -- Get both the user object and its reference
   select value(u),
          ref(u)
     into
      v_employee,
      v_user_ref
     from users u
    where u.userid = p_userid;

   -- Verify the user has employee role
   if v_employee.role != 'employee' then
      raise_application_error(
         -20009,
         'User '
         || p_userid
         || ' is not an employee'
      );
   end if;

   -- Insert the employee
   insert into employees values ( employee_type(
      v_employee.userid,
      v_employee.name,
      v_employee.email,
      v_employee.contact,
      v_employee.address,
      v_employee.role,
      v_employee.joined_at,
      p_employeeid,
      v_user_ref
   ) );

   commit;
   dbms_output.put_line('Employee '
                        || p_employeeid
                        || ' added successfully');
exception
   when no_data_found then
      raise_application_error(
         -20010,
         'User '
         || p_userid
         || ' not found'
      );
   when others then
      raise_application_error(
         -20011,
         'Error adding employee: ' || sqlerrm
      );
end;
/
create or replace procedure add_product_category (
   p_categoryid   in varchar2,
   p_categoryname in varchar2,
   p_description  in varchar2
) as
begin
   insert into product_categories values ( product_category_type(
      p_categoryid,
      p_categoryname,
      p_description
   ) );
   commit;
   dbms_output.put_line('Product category '
                        || p_categoryname
                        || ' added successfully');
end;
/
create or replace procedure add_product (
   p_productid     in varchar2,
   p_productname   in varchar2,
   p_price         in varchar2,
   p_categoryid    in varchar2,
   p_stockquantity in number,
   p_status        in varchar2,
   p_sellerid      in varchar2
) as
   v_category   product_category_type;
   v_seller_ref ref seller_type;
begin
   select value(pc)
     into v_category
     from product_categories pc
    where pc.categoryid = p_categoryid;

   insert into products values ( product_type(
      p_productid,
      p_productname,
      p_price,
      v_category,
      p_stockquantity,
      p_status,
      sysdate,
      sysdate,
      v_seller_ref
   ) );
   commit;
   dbms_output.put_line('Product '
                        || p_productname
                        || ' added successfully');
end;
/
create or replace procedure add_payment (
   p_paymentid         in varchar2,
   p_amount            in float,
   p_transactionstatus in varchar2
) as
begin
   insert into payments values ( payment_type(
      p_paymentid,
      p_amount,
      p_transactionstatus
   ) );
end;
/
create or replace procedure add_shipping (
   p_shippingid     in varchar2,
   p_trackingno     in varchar2,
   p_deliverystatus in varchar2,
   p_street         in varchar2,
   p_city           in varchar2,
   p_district       in varchar2
) as
   v_address address_type;
begin
   v_address := address_type(
      p_street,
      p_city,
      p_district
   );
   insert into shippings values ( shipping_type(
      p_shippingid,
      p_trackingno,
      p_deliverystatus,
      v_address,
      sysdate,
      sysdate
   ) );
end;
/
create or replace procedure add_warehouse (
   p_warehouseid in varchar2,
   p_location    in varchar2,
   p_capacity    in integer,
   p_employeeid  in varchar2
) as
   v_employee_ref ref employee_type;
begin
   select ref(e)
     into v_employee_ref
     from employees e
    where e.employeeid = p_employeeid;

   insert into warehouses values ( warehouse_type(
      p_warehouseid,
      p_location,
      p_capacity,
      v_employee_ref
   ) );
   commit;
   dbms_output.put_line('Warehouse '
                        || p_warehouseid
                        || ' added successfully');
exception
   when no_data_found then
      raise_application_error(
         -20008,
         'Employee with ID '
         || p_employeeid
         || ' not found.'
      );
   when others then
      raise;
end;
/

--------Function to generate an invoice--------
create or replace function generate_invoice (
   p_orderid in varchar2
) return varchar2 is
   v_invoice          varchar2(4000);
   v_customer_name    varchar2(50);
   v_customer_email   varchar2(100);
   v_customer_address varchar2(200);
   v_shipping_address varchar2(200);
   v_shipping_status  varchar2(20);
   v_payment_amount   number(
      10,
      2
   );
   v_payment_status   varchar2(20);
   v_order_date       date;
   v_total            number(
      10,
      2
   ) := 0;
   v_line_item        varchar2(200);
   v_line_items       varchar2(2000) := '';
   v_count            number := 0;
   cursor order_items is
   select o.orderid,
          deref(o.product).productname as product_name,
          deref(o.product).price as price,
          o.quantity,
          to_number(deref(o.product).price) * o.quantity as subtotal
     from orders o
    where o.orderid like p_orderid || '%'
    order by o.orderid;

begin
    -- Fetch customer and order details (using the first row for shared details)
   begin
      select deref(o.customerid).name,
             deref(o.customerid).email,
             deref(o.customerid).address.get_full_address(),
             deref(o.shipping).address.get_full_address(),
             deref(o.shipping).deliverystatus,
             o.payment.amount,
             o.payment.transactionstatus,
             o.orderdate
        into
         v_customer_name,
         v_customer_email,
         v_customer_address,
         v_shipping_address,
         v_shipping_status,
         v_payment_amount,
         v_payment_status,
         v_order_date
        from orders o
       where o.orderid like p_orderid || '%'
         and rownum = 1; -- Get shared details from the first matching row
   exception
      when no_data_found then
         return 'Error: No order found for ID ' || p_orderid;
      when others then
         return 'Error generating invoice: ' || sqlerrm;
   end;

    -- Build invoice header
   v_invoice := 'INVOICE'
                || chr(10)
                || '-------'
                || chr(10)
                || 'Order ID: '
                || p_orderid
                || chr(10)
                || 'Order Date: '
                || to_char(
      v_order_date,
      'DD-MON-YYYY'
   )
                || chr(10)
                || 'Customer: '
                || v_customer_name
                || ' ('
                || v_customer_email
                || ')'
                || chr(10)
                || 'Billing Address: '
                || v_customer_address
                || chr(10)
                || 'Shipping Address: '
                || v_shipping_address
                || chr(10)
                || 'Shipping Status: '
                || v_shipping_status
                || chr(10)
                || 'Payment Status: '
                || v_payment_status
                || chr(10)
                || chr(10)
                || 'Items:'
                || chr(10)
                || '---------------------------------------------'
                || chr(10)
                || rpad(
      'Product',
      20
   )
                || rpad(
      'Quantity',
      10
   )
                || rpad(
      'Price',
      10
   )
                || 'Subtotal'
                || chr(10)
                || '---------------------------------------------'
                || chr(10);

    -- Fetch and format line items
   for item in order_items loop
      v_line_item := rpad(
         item.product_name,
         20
      )
                     || rpad(
         to_char(item.quantity),
         10
      )
                     || rpad(
         item.price,
         10
      )
                     || to_char(
         item.subtotal,
         '9999.99'
      )
                     || chr(10);
      v_line_items := v_line_items || v_line_item;
      v_total := v_total + item.subtotal;
      v_count := v_count + 1;
   end loop;

   if v_count = 0 then
      return 'Error: No items found for order ID ' || p_orderid;
   end if;

    -- Append line items and total
   v_invoice := v_invoice
                || v_line_items
                || '---------------------------------------------'
                || chr(10)
                || 'Total: '
                || to_char(
      v_total,
      '9999.99'
   )
                || chr(10);

    -- Validate payment amount
   if abs(v_total - v_payment_amount) > 0.01 then
      v_invoice := v_invoice
                   || chr(10)
                   || 'Warning: Payment amount ('
                   || to_char(
         v_payment_amount,
         '9999.99'
      )
                   || ') does not match total ('
                   || to_char(
         v_total,
         '9999.99'
      )
                   || ')';
   end if;

   return v_invoice;
exception
   when others then
      return 'Error generating invoice: ' || sqlerrm;
end;
/

-- Sample implementation of `generate_invoice` function
select generate_invoice('ORD--000001') as invoice
  from dual;


----------- Insertion statements---------------
-- 1. users
insert into users values ( base_user_type(
   'U001',
   'Pako Mampane',
   'pako@gmail.com',
   '71234567',
   address_type(
      '123 Mogoma St',
      'Gaborone',
      'SE'
   ),
   'customer',
   sysdate - 100
) );
insert into users values ( base_user_type(
   'U002',
   'Carol Maundo',
   'carol@gmail.com',
   '72345678',
   address_type(
      '456 Thito St',
      'Gaborone',
      'SE'
   ),
   'customer',
   sysdate - 95
) );
insert into users values ( base_user_type(
   'U003',
   'Thabiso Podi',
   'thabiso@gmail.com',
   '73456789',
   address_type(
      '789 Bojanala St',
      'Gaborone',
      'SE'
   ),
   'customer',
   sysdate - 90
) );
insert into users values ( base_user_type(
   'U004',
   'Lefika Paulson',
   'lefika@gmail.com',
   '74567890',
   address_type(
      '321 Khama St',
      'Gaborone',
      'SE'
   ),
   'employee',
   sysdate - 85
) );
insert into users values ( base_user_type(
   'U005',
   'Boris Mathata',
   'boris@gmail.com',
   '74567890',
   address_type(
      '654 Lerole St',
      'Gaborone',
      'SE'
   ),
   'customer',
   sysdate - 80
) );
insert into users values ( base_user_type(
   'U006',
   'Tom Harris',
   'tom@gmail.com',
   '74567890',
   address_type(
      '987 Mathata St',
      'Francistown',
      'NE'
   ),
   'seller',
   sysdate - 75
) );
insert into users values ( base_user_type(
   'U007',
   'Tkay Nyams',
   'tkay@gmail.com',
   '74567890',
   address_type(
      '147 Sekgoma St',
      'Francistown',
      'NE'
   ),
   'customer',
   sysdate - 70
) );
insert into users values ( base_user_type(
   'U008',
   'David Bolele',
   'david@gmail.com',
   '78901234',
   address_type(
      '258 Bakgatla St',
      'Francistown',
      'NE'
   ),
   'employee',
   sysdate - 65
) );
insert into users values ( base_user_type(
   'U009',
   'Bonya Maraks',
   'bonya@gmail.com',
   '79012345',
   address_type(
      '369 Lesedi St',
      'Francistown',
      'NE'
   ),
   'customer',
   sysdate - 60
) );
   insert into users values ( base_user_type(
      'U010',
      'Thuto Lesedi',
      'thuto@gmail.com',
      '72123456',
      address_type(
         '741 Koma St',
         'Francistown',
         'NE'
      ),
      'seller',
      sysdate - 55
   ) );
/


-- 2. Customers
begin
   add_customer(
      'U001',
      'C001'
   );
   add_customer(
      'U002',
      'C002'
   );
   add_customer(
      'U003',
      'C003'
   );
   add_customer(
      'U005',
      'C004'
   );
end;
/
-- 3. sellers
begin
   add_seller(
      'U006',
      'S001'
   );
   add_seller(
      'U010',
      'S002'
   );
end;
/

-- 4. employees
begin
   add_employee(
      'U004',
      'E001'
   );
   add_employee(
      'U008',
      'E002'
   );
end;
/

-- 5. product_categories
begin
   add_product_category(
      'CAT001',
      'Electronics',
      'Electronic devices'
   );
   add_product_category(
      'CAT002',
      'Clothing',
      'Fashion items'
   );
   add_product_category(
      'CAT003',
      'Books',
      'Literature and textbooks'
   );
   add_product_category(
      'CAT004',
      'Toys',
      'Children toys'
   );
   add_product_category(
      'CAT005',
      'Furniture',
      'Home furniture'
   );
   add_product_category(
      'CAT006',
      'Appliances',
      'Kitchen appliances'
   );
   add_product_category(
      'CAT007',
      'Sports',
      'Sporting goods'
   );
   add_product_category(
      'CAT008',
      'Jewelry',
      'Fashion jewelry'
   );
   add_product_category(
      'CAT009',
      'Beauty',
      'Beauty products'
   );
   add_product_category(
      'CAT010',
      'Automotive',
      'Car accessories'
   );
end;
/

-- 6. products
begin
   add_product(
      'P001',
      'Laptop',
      '999.99',
      'CAT001',
      50,
      'available',
      'S001'
   );
   add_product(
      'P002',
      'T-Shirt',
      '19.99',
      'CAT002',
      100,
      'available',
      'S001'
   );
   add_product(
      'P003',
      'Book',
      '29.99',
      'CAT003',
      30,
      'available',
      'S001'
   );
   add_product(
      'P004',
      'Toy Car',
      '15.99',
      'CAT004',
      80,
      'available',
      'S001'
   );
   add_product(
      'P005',
      'Chair',
      '89.99',
      'CAT005',
      20,
      'available',
      'S001'
   );
   add_product(
      'P006',
      'Blender',
      '49.99',
      'CAT006',
      40,
      'available',
      'S002'
   );
   add_product(
      'P007',
      'Tennis Racket',
      '39.99',
      'CAT007',
      60,
      'available',
      'S002'
   );
   add_product(
      'P008',
      'Necklace',
      '199.99',
      'CAT008',
      10,
      'available',
      'S002'
   );
   add_product(
      'P009',
      'Lipstick',
      '9.99',
      'CAT009',
      200,
      'available',
      'S002'
   );
   add_product(
      'P010',
      'Car Mat',
      '24.99',
      'CAT010',
      70,
      'available',
      'S002'
   );
end;
/
-- 7. warehouses
begin
   add_warehouse(
      'W001',
      'Gaborone',
      1000,
      'E001'
   );
   add_warehouse(
      'W002',
      'Gaborone',
      800,
      'E002'
   );
end;
/
-- 8. orders;
begin
   -- Call place_order for customer C001 ordering 2 units of P001 (Laptop) and 1 unit of P002 (T-Shirt)
   place_order(
      p_customerid => 'C001',
      p_productids => sys.odcivarchar2list(
         'P001',
         'P002'
      ),
      p_payment    => payment_type(
         'PAY014',
         0,
         'pending'
      ), -- Amount is placeholder; actual amounts set per order
      p_shipping   => shipping_type(
         'SHIP010',
         'TRACK010',
         'pending',
         address_type(
            '789 Bojanala St',
            'Gaborone',
            'SE'
         ),
         sysdate,
         sysdate
      ),
      p_quantities => sys.odcinumberlist(
         2,
         1
      )
   );

   -- Call place_order for customer C002 ordering 3 units of P003 (Book)
   place_order(
      p_customerid => 'C002',
      p_productids => sys.odcivarchar2list('P003'),
      p_payment    => payment_type(
         'PAY015',
         0,
         'completed'
      ), -- Amount is placeholder
      p_shipping   => shipping_type(
         'SHIP011',
         'TRACK011',
         'pending',
         address_type(
            '456 Thito St',
            'Gaborone',
            'SE'
         ),
         sysdate,
         sysdate
      ),
      p_quantities => sys.odcinumberlist(3)
   );

   -- Call place_order for customer C003 ordering 1 unit of P004 (Toy Car)
   place_order(
      p_customerid => 'C003',
      p_productids => sys.odcivarchar2list('P004'),
      p_payment    => payment_type(
         'PAY016',
         0,
         'pending'
      ), -- Amount is placeholder
      p_shipping   => shipping_type(
         'SHIP012',
         'TRACK012',
         'pending',
         address_type(
            '789 Bojanala St',
            'Gaborone',
            'SE'
         ),
         sysdate,
         sysdate
      ),
      p_quantities => sys.odcinumberlist(1)
   );

   commit;
   dbms_output.put_line('Orders placed successfully');
exception
   when others then
      dbms_output.put_line('Error: '
                           || sqlerrm
                           || ' at '
                           || dbms_utility.format_error_backtrace);
      rollback;
end;
/